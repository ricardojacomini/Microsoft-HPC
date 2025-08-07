# Install and Enable InfiniBand/RDMA on H-Series VMs
# This script installs Mellanox WinOF-2 drivers and enables RDMA capabilities
# Can be run locally on the VM or executed remotely via Azure CLI
# 
# ✨ Enhanced with Pre-Installation Verification:
# - Automatically checks if RDMA is already configured
# - Skips installation if RDMA is working properly
# - Provides detailed status reporting
#
# Usage Examples:
#   .\install-infiniband-rdma.ps1                                    # Run locally on VM
#   .\install-infiniband-rdma.ps1 -RemoteExecution -ResourceGroup "rg-name" -VmName "vm-name"  # Run remotely
#   .\install-infiniband-rdma.ps1 -DriverUrl "custom-url"            # Use custom driver URL
#   .\install-infiniband-rdma.ps1 -SkipReboot                        # Skip automatic reboot
#   .\install-infiniband-rdma.ps1 -WhatIf                            # Dry run

param(
    [string]$DriverUrl = "https://content.mellanox.com/WinOF/MLNX_WinOF2-25_4_50020_All_x64.exe",
    [string]$DownloadPath = "C:\Temp\InfiniBand",
    [string]$DriverInstaller = "MLNX_WinOF2-latest.exe",
    [switch]$SkipReboot,
    [switch]$WhatIf,
    [switch]$RemoteExecution,
    [string]$ResourceGroup,
    [string]$VmName,
    [switch]$Force
)

# =============================== #
# Function Definitions            #
# =============================== #

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Write-Output $logMessage
    
    # Also write to event log if running locally
    if (-not $RemoteExecution -and $Level -eq "ERROR") {
        try {
            Write-EventLog -LogName Application -Source "InfiniBand-RDMA" -EventId 1001 -EntryType Error -Message $Message -ErrorAction SilentlyContinue
        } catch { }
    }
}

function Test-InfiniBandSupport {
    Write-Log "Checking if VM supports InfiniBand..."
    
    # Check VM size/SKU
    try {
        $vmSize = (Invoke-RestMethod -Headers @{"Metadata"="true"} -URI "http://169.254.169.254/metadata/instance/compute/vmSize?api-version=2021-02-01" -Method GET).ToUpper()
        Write-Log "Detected VM Size: $vmSize"
        
        $supportedSizes = @(
            "STANDARD_HC44RS", "STANDARD_HC44-16RS", "STANDARD_HC44-32RS",
            "STANDARD_HB120RS_V3", "STANDARD_HB120-16RS_V3", "STANDARD_HB120-32RS_V3", "STANDARD_HB120-64RS_V3",
            "STANDARD_HB176RS_V4", "STANDARD_HB60RS", "STANDARD_ND40RS_V2"
        )
        
        if ($supportedSizes -contains $vmSize) {
            Write-Log "✅ VM size $vmSize supports InfiniBand" "INFO"
            return $true
        } else {
            Write-Log "⚠️  VM size $vmSize may not support InfiniBand" "WARN"
            if (-not $Force) {
                $continue = Read-Host "Continue anyway? (Y/N)"
                return ($continue -eq "Y" -or $continue -eq "y")
            }
            return $true
        }
    } catch {
        Write-Log "Could not determine VM size. Assuming InfiniBand support." "WARN"
        return $true
    }
}

function Test-AcceleratedNetworking {
    Write-Log "Checking for accelerated networking..."
    
    try {
        $adapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" -and $_.InterfaceDescription -like "*Mellanox*" }
        if ($adapters) {
            Write-Log "✅ Found potential InfiniBand adapters" "INFO"
            $adapters | ForEach-Object {
                Write-Log "   - $($_.Name): $($_.InterfaceDescription) ($($_.LinkSpeed))" "INFO"
            }
            return $true
        } else {
            Write-Log "⚠️  No Mellanox adapters found yet" "WARN"
            return $false
        }
    } catch {
        Write-Log "Could not check network adapters: $($_.Exception.Message)" "WARN"
        return $false
    }
}

function Install-InfiniBandDrivers {
    param(
        [string]$Url,
        [string]$Path,
        [string]$Installer,
        [switch]$WhatIf
    )
    
    if ($WhatIf) {
        Write-Log "[DRY-RUN] Would download and install InfiniBand drivers"
        Write-Log "[DRY-RUN] Download URL: $Url"
        Write-Log "[DRY-RUN] Install Path: $Path"
        return $true
    }
    
    Write-Log "Starting InfiniBand driver installation..."
    
    # Create download directory
    if (!(Test-Path $Path)) {
        try {
            New-Item -ItemType Directory -Path $Path -Force | Out-Null
            Write-Log "Created directory: $Path"
        } catch {
            Write-Log "Failed to create directory $Path : $($_.Exception.Message)" "ERROR"
            return $false
        }
    }
    
    # Download drivers
    $installerPath = Join-Path $Path $Installer
    Write-Log "Downloading Mellanox InfiniBand drivers from: $Url"
    try {
        # Use TLS 1.2 for modern HTTPS
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        
        Invoke-WebRequest -Uri $Url -OutFile $installerPath -UseBasicParsing -TimeoutSec 300
        Write-Log "✅ Driver download completed: $installerPath"
        
        # Verify file exists and has reasonable size
        $fileInfo = Get-Item $installerPath
        if ($fileInfo.Length -gt 10MB) {
            Write-Log "Driver file size: $([math]::Round($fileInfo.Length / 1MB, 2)) MB"
        } else {
            Write-Log "Warning: Driver file seems small ($($fileInfo.Length) bytes)" "WARN"
        }
    } catch {
        Write-Log "Failed to download drivers: $($_.Exception.Message)" "ERROR"
        return $false
    }
    
    # Install drivers
    Write-Log "Installing InfiniBand drivers (silent installation)..."
    try {
        $installArgs = @("/S", "/v/qn")
        $process = Start-Process -FilePath $installerPath -ArgumentList $installArgs -Wait -PassThru -NoNewWindow
        
        if ($process.ExitCode -eq 0) {
            Write-Log "✅ Driver installation completed successfully"
        } elseif ($process.ExitCode -eq 3010) {
            Write-Log "✅ Driver installation completed (reboot required)"
        } else {
            Write-Log "Driver installation completed with exit code: $($process.ExitCode)" "WARN"
        }
        
        # Wait for installation to settle
        Start-Sleep -Seconds 15
        
    } catch {
        Write-Log "Driver installation failed: $($_.Exception.Message)" "ERROR"
        return $false
    }
    
    # Cleanup installer
    try {
        Remove-Item $installerPath -Force -ErrorAction SilentlyContinue
        Write-Log "Cleaned up installer file"
    } catch { }
    
    return $true
}

function Test-RDMAConfiguration {
    Write-Log "Verifying RDMA configuration..."
    
    try {
        # Check for Mellanox devices
        $mellanoxDevices = Get-WmiObject Win32_PnPSignedDriver | Where-Object { 
            $_.DeviceName -like '*Mellanox*' -or 
            $_.DeviceName -like '*ConnectX*' -or
            $_.DeviceName -like '*InfiniBand*'
        }
        
        if ($mellanoxDevices) {
            Write-Log "✅ Mellanox InfiniBand devices detected:"
            $mellanoxDevices | ForEach-Object {
                Write-Log "   - $($_.DeviceName) (Driver: $($_.DriverVersion))"
            }
        } else {
            Write-Log "⚠️  No Mellanox devices found" "WARN"
        }
        
        # Check RDMA adapters
        Write-Log "Checking RDMA adapter status..."
        $rdmaAdapters = Get-NetAdapterRdma -ErrorAction SilentlyContinue
        if ($rdmaAdapters) {
            $enabledAdapters = $rdmaAdapters | Where-Object { $_.Enabled -eq $true }
            if ($enabledAdapters) {
                Write-Log "✅ RDMA is enabled:"
                $enabledAdapters | ForEach-Object {
                    Write-Log "   - $($_.Name): Enabled=$($_.Enabled), MaxQueuePairs=$($_.MaxQueuePairs)"
                }
            } else {
                Write-Log "⚠️  RDMA adapters found but not enabled:" "WARN"
                $rdmaAdapters | ForEach-Object {
                    Write-Log "   - $($_.Name): Enabled=$($_.Enabled)"
                }
            }
        } else {
            Write-Log "⚠️  No RDMA adapters found" "WARN"
        }
        
        # Check network adapters
        Write-Log "Network adapter summary:"
        $networkAdapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }
        $networkAdapters | ForEach-Object {
            $speed = if ($_.LinkSpeed) { $_.LinkSpeed } else { "Unknown" }
            Write-Log "   - $($_.Name): $($_.InterfaceDescription) ($speed)"
        }
        
        # Check SMB network interfaces
        Write-Log "Checking SMB network interfaces..."
        $smbInterfaces = Get-SmbClientNetworkInterface -ErrorAction SilentlyContinue
        if ($smbInterfaces) {
            $rdmaCapable = $smbInterfaces | Where-Object { $_.RdmaCapable -eq $true }
            if ($rdmaCapable) {
                Write-Log "✅ SMB RDMA-capable interfaces found:"
                $rdmaCapable | ForEach-Object {
                    Write-Log "   - Interface $($_.InterfaceIndex): RDMA=$($_.RdmaCapable), RSS=$($_.RssCapable)"
                }
            } else {
                Write-Log "⚠️  No RDMA-capable SMB interfaces found" "WARN"
            }
        }
        
        return ($enabledAdapters -and $enabledAdapters.Count -gt 0)
        
    } catch {
        Write-Log "Error during RDMA verification: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Enable-RDMAFeatures {
    Write-Log "Enabling RDMA features and optimizations..."
    
    try {
        # Enable RDMA on all capable adapters
        $rdmaAdapters = Get-NetAdapterRdma -ErrorAction SilentlyContinue
        if ($rdmaAdapters) {
            $rdmaAdapters | ForEach-Object {
                if (-not $_.Enabled) {
                    try {
                        Enable-NetAdapterRdma -Name $_.Name -ErrorAction Stop
                        Write-Log "✅ Enabled RDMA on adapter: $($_.Name)"
                    } catch {
                        Write-Log "Failed to enable RDMA on $($_.Name): $($_.Exception.Message)" "WARN"
                    }
                }
            }
        }
        
        # Set SMB configuration for RDMA
        Write-Log "Configuring SMB for RDMA..."
        try {
            Set-SmbClientConfiguration -EnableMultiChannel $true -Confirm:$false -ErrorAction SilentlyContinue
            Write-Log "✅ Enabled SMB multi-channel"
        } catch {
            Write-Log "Could not configure SMB multi-channel: $($_.Exception.Message)" "WARN"
        }
        
        # Disable bandwidth throttling for RDMA
        try {
            Set-SmbClientConfiguration -EnableBandwidthThrottling $false -Confirm:$false -ErrorAction SilentlyContinue
            Write-Log "✅ Disabled SMB bandwidth throttling"
        } catch { }
        
        return $true
        
    } catch {
        Write-Log "Error enabling RDMA features: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Invoke-RemoteInstallation {
    param(
        [string]$ResourceGroupName,
        [string]$VmName
    )
    
    Write-Log "Executing remote installation on VM: $VmName in resource group: $ResourceGroupName"
    
    # Create the script content for remote execution
    $remoteScript = @"
# Remote InfiniBand/RDMA Installation Script
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process -Force

Write-Output "🔍 Checking current RDMA configuration..."

# First, check if RDMA is already working
try {
    `$rdmaAdapters = Get-NetAdapterRdma -ErrorAction SilentlyContinue
    `$enabledAdapters = `$rdmaAdapters | Where-Object { `$_.Enabled -eq `$true }
    
    `$smbInterfaces = Get-SmbClientNetworkInterface -ErrorAction SilentlyContinue
    `$rdmaCapable = `$smbInterfaces | Where-Object { `$_.RdmaCapable -eq `$true }
    
    if (`$enabledAdapters -and `$enabledAdapters.Count -gt 0 -and `$rdmaCapable -and `$rdmaCapable.Count -gt 0) {
        Write-Output "✅ RDMA is already properly configured and working!"
        Write-Output "ℹ️  Installation step will be skipped."
        Write-Output ""
        Write-Output "Current RDMA configuration:"
        
        Write-Output "RDMA Adapters:"
        `$enabledAdapters | ForEach-Object {
            Write-Output "   - `$(`$_.Name): Enabled=`$(`$_.Enabled), MaxQueuePairs=`$(`$_.MaxQueuePairs)"
        }
        
        Write-Output "SMB RDMA Interfaces:"
        `$rdmaCapable | ForEach-Object {
            Write-Output "   - Interface `$(`$_.InterfaceIndex): RDMA=`$(`$_.RdmaCapable), LinkSpeed=`$(`$_.LinkSpeed)"
        }
        
        Write-Output "Network Adapters:"
        Get-NetAdapter | Where-Object { `$_.Status -eq 'Up' -and `$_.InterfaceDescription -like '*Mellanox*' } | ForEach-Object {
            Write-Output "   - `$(`$_.Name): `$(`$_.InterfaceDescription) (`$(`$_.LinkSpeed))"
        }
        
        Write-Output ""
        Write-Output "✅ System verification completed - RDMA is ready for use!"
        Write-Output "No installation needed."
        exit 0
    } else {
        Write-Output "⚠️  RDMA is not fully configured. Proceeding with installation..."
    }
} catch {
    Write-Output "Could not verify RDMA status. Proceeding with installation..."
}

# Download this script and execute locally
`$scriptUrl = 'https://raw.githubusercontent.com/ricardojacomini/Microsoft-HPC/main/Azure_HPC_VMs/install-infiniband-rdma.ps1'
`$localScript = 'C:\Temp\install-infiniband-rdma.ps1'

try {
    # Create temp directory
    New-Item -ItemType Directory -Path 'C:\Temp' -Force -ErrorAction SilentlyContinue
    
    # Download script
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri '`$scriptUrl' -OutFile '`$localScript' -UseBasicParsing
    
    # Execute script locally
    & `$localScript -DriverUrl '$DriverUrl' -DownloadPath '$DownloadPath' -SkipReboot:`$$SkipReboot -Force:`$$Force
    
} catch {
    Write-Output "Remote execution failed: `$(`$_.Exception.Message)"
    
    # Fallback: inline execution
    Write-Output "Falling back to inline execution..."
    
    # Inline driver installation
    `$driverUrl = '$DriverUrl'
    `$downloadPath = '$DownloadPath'
    `$installer = '$DriverInstaller'
    
    if (!(Test-Path `$downloadPath)) { New-Item -ItemType Directory -Path `$downloadPath -Force }
    
    Write-Output "Downloading drivers..."
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri `$driverUrl -OutFile "`$downloadPath\`$installer" -UseBasicParsing
    
    Write-Output "Installing drivers..."
    Start-Process -FilePath "`$downloadPath\`$installer" -ArgumentList '/S', '/v/qn' -Wait
    
    Write-Output "Verifying installation..."
    Start-Sleep -Seconds 30
    Get-NetAdapterRdma | Format-Table Name, Enabled, MaxQueuePairs -AutoSize
    Get-NetAdapter | Where-Object { `$_.InterfaceDescription -like '*Mellanox*' } | Format-Table Name, InterfaceDescription, LinkSpeed, Status -AutoSize
}
"@
    
    try {
        Write-Log "Executing remote command via Azure CLI..."
        $result = az vm run-command invoke --resource-group $ResourceGroupName --name $VmName --command-id "RunPowerShellScript" --scripts $remoteScript --output json | ConvertFrom-Json
        
        if ($result.value) {
            Write-Log "Remote execution completed. Output:"
            $result.value | ForEach-Object {
                if ($_.message) {
                    $_.message -split "`n" | ForEach-Object { Write-Log "   $_" }
                }
            }
            return $true
        } else {
            Write-Log "No output received from remote execution" "WARN"
            return $false
        }
    } catch {
        Write-Log "Remote execution failed: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# =============================== #
# Main Execution                  #
# =============================== #

Write-Log "🚀 InfiniBand/RDMA Installation and Configuration Script"
Write-Log "========================================================="
Write-Log ""

# Handle remote execution
if ($RemoteExecution) {
    if (-not $ResourceGroup -or -not $VmName) {
        Write-Log "Error: ResourceGroup and VmName are required for remote execution" "ERROR"
        Write-Log "Usage: .\install-infiniband-rdma.ps1 -RemoteExecution -ResourceGroup 'rg-name' -VmName 'vm-name'"
        exit 1
    }
    
    $success = Invoke-RemoteInstallation -ResourceGroupName $ResourceGroup -VmName $VmName
    if ($success) {
        Write-Log "✅ Remote installation completed successfully"
    } else {
        Write-Log "❌ Remote installation failed" "ERROR"
        exit 1
    }
    exit 0
}

# Local execution
Write-Log "Configuration:"
Write-Log "  Driver URL: $DriverUrl"
Write-Log "  Download Path: $DownloadPath"
Write-Log "  Skip Reboot: $SkipReboot"
Write-Log "  What If: $WhatIf"
Write-Log ""

# Pre-installation checks
if (-not $WhatIf) {
    $supported = Test-InfiniBandSupport
    if (-not $supported) {
        Write-Log "InfiniBand support check failed. Exiting." "ERROR"
        exit 1
    }
    
    Write-Log "🔍 Checking current RDMA configuration..."
    $rdmaAlreadyWorking = Test-RDMAConfiguration
    
    if ($rdmaAlreadyWorking) {
        Write-Log "✅ RDMA is already properly configured and working!"
        Write-Log "ℹ️  Installation step will be skipped."
        Write-Log ""
        
        # Show current configuration for verification
        Write-Log "Current RDMA status verified:"
        Test-AcceleratedNetworking | Out-Null
        
        Write-Log ""
        Write-Log "✅ System verification completed - RDMA is ready for use!"
        Write-Log ""
        Write-Log "Useful verification commands:"
        Write-Log "  Get-NetAdapterRdma"
        Write-Log "  Get-SmbClientNetworkInterface"
        Write-Log "  Get-NetAdapter | Where-Object { `$_.InterfaceDescription -like '*Mellanox*' }"
        Write-Log ""
        Write-Log "Script completed - no installation needed."
        exit 0
    } else {
        Write-Log "⚠️  RDMA is not fully configured. Proceeding with installation..."
        Write-Log "Checking current adapter status..."
        Test-AcceleratedNetworking | Out-Null
    }
}

# Install drivers
Write-Log "Installing InfiniBand drivers..."
$installSuccess = Install-InfiniBandDrivers -Url $DriverUrl -Path $DownloadPath -Installer $DriverInstaller -WhatIf:$WhatIf

if (-not $installSuccess -and -not $WhatIf) {
    Write-Log "Driver installation failed. Exiting." "ERROR"
    exit 1
}

if (-not $WhatIf) {
    # Wait for driver installation to complete
    Write-Log "Waiting for driver installation to complete..."
    Start-Sleep -Seconds 30
    
    # Enable RDMA features
    Write-Log "Enabling RDMA features..."
    Enable-RDMAFeatures | Out-Null
    
    # Final verification
    Write-Log "Performing final verification..."
    $rdmaWorking = Test-RDMAConfiguration
    
    if ($rdmaWorking) {
        Write-Log "✅ InfiniBand/RDMA installation and configuration completed successfully!"
    } else {
        Write-Log "⚠️  Installation completed but RDMA may need additional configuration" "WARN"
    }
    
    # Reboot recommendation
    if (-not $SkipReboot) {
        Write-Log ""
        Write-Log "🔄 A reboot is recommended to ensure all drivers are properly loaded."
        $reboot = Read-Host "Reboot now? (Y/N)"
        if ($reboot -eq "Y" -or $reboot -eq "y") {
            Write-Log "Rebooting system..."
            Restart-Computer -Force
        }
    }
} else {
    Write-Log "[DRY-RUN] All checks completed. No changes made."
}

Write-Log ""
Write-Log "Useful verification commands:"
Write-Log "  Get-NetAdapterRdma"
Write-Log "  Get-SmbClientNetworkInterface"
Write-Log "  Get-NetAdapter | Where-Object { \$_.InterfaceDescription -like '*Mellanox*' }"
Write-Log ""
Write-Log "Script completed."
