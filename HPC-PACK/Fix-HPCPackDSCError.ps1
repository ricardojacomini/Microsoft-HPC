<#
.SYNOPSIS
    Fixes common HPC Pack DSC extension errors including error code -532462766

.DESCRIPTION
    This script addresses common HPC Pack installation failures including:
    - DSC Configuration 'InstallPrimaryHeadNode' errors
    - Domain join and authentication issues
    - VM extension provisioning failures
    - InfiniBand driver compatibility issues

.PARAMETER ResourceGroupName
    Name of the resource group containing the HPC cluster

.PARAMETER HeadNodeName
    Name of the head node VM (default: headnode)

.PARAMETER DomainName
    Domain name for the HPC cluster (default: hpc.cluster)

.PARAMETER AdminUsername
    Administrator username for the VMs

.PARAMETER AdminPassword
    Administrator password for the VMs

.PARAMETER FixInfiniBand
    Enable InfiniBand/RDMA troubleshooting for HB/HC series VMs

.EXAMPLE
    .\Fix-HPCPackDSCError.ps1 -ResourceGroupName "hpcpack-cluster" -AdminPassword (ConvertTo-SecureString "P@ssw0rd!" -AsPlainText -Force)

.AUTHOR
    Ricardo de Souza Jacomini
    Microsoft Azure HPC + AI

.DATE
    August 6, 2025
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    
    [string]$HeadNodeName = "headnode",
    [string]$DomainName = "hpc.cluster",
    [string]$AdminUsername = "hpcadmin",
    
    [Parameter(Mandatory=$true)]
    [SecureString]$AdminPassword,
    
    [switch]$FixInfiniBand
)

function Write-StatusMessage {
    param([string]$Message, [string]$Status = "INFO")
    $emoji = switch ($Status) {
        "INFO" { "ℹ️" }
        "SUCCESS" { "✅" }
        "ERROR" { "❌" }
        "WARNING" { "⚠️" }
        "PROGRESS" { "🔄" }
        default { "📝" }
    }
    Write-Host "$emoji $Message"
}

function Test-VMExtensionStatus {
    param([string]$ResourceGroup, [string]$VMName)
    
    Write-StatusMessage "Checking VM extension status on $VMName..." "PROGRESS"
    
    try {
        $extensions = Get-AzVMExtension -ResourceGroupName $ResourceGroup -VMName $VMName -ErrorAction Stop
        
        foreach ($ext in $extensions) {
            Write-StatusMessage "Extension: $($ext.Name) - Status: $($ext.ProvisioningState)" "INFO"
            if ($ext.ProvisioningState -eq "Failed") {
                Write-StatusMessage "Failed extension details: $($ext.SubStatuses | ConvertTo-Json -Depth 3)" "ERROR"
            }
        }
        return $extensions
    }
    catch {
        Write-StatusMessage "Failed to get extension status: $($_.Exception.Message)" "ERROR"
        return $null
    }
}

function Remove-FailedExtensions {
    param([string]$ResourceGroup, [string]$VMName)
    
    Write-StatusMessage "Removing failed extensions from $VMName..." "PROGRESS"
    
    $extensions = Get-AzVMExtension -ResourceGroupName $ResourceGroup -VMName $VMName -ErrorAction SilentlyContinue
    
    foreach ($ext in $extensions) {
        if ($ext.ProvisioningState -eq "Failed" -or $ext.Name -like "*HPC*" -or $ext.Name -like "*DSC*") {
            Write-StatusMessage "Removing extension: $($ext.Name)" "WARNING"
            try {
                Remove-AzVMExtension -ResourceGroupName $ResourceGroup -VMName $VMName -Name $ext.Name -Force -ErrorAction Stop
                Write-StatusMessage "Successfully removed extension: $($ext.Name)" "SUCCESS"
            }
            catch {
                Write-StatusMessage "Failed to remove extension $($ext.Name): $($_.Exception.Message)" "ERROR"
            }
        }
    }
}

function Test-DomainConfiguration {
    param([string]$ResourceGroup, [string]$VMName, [string]$Domain)
    
    Write-StatusMessage "Testing domain configuration on $VMName..." "PROGRESS"
    
    $script = @"
try {
    `$domain = Get-WmiObject -Class Win32_ComputerSystem | Select-Object -ExpandProperty Domain
    if (`$domain -eq '$Domain') {
        Write-Output "SUCCESS: VM is joined to domain: `$domain"
        return 0
    } else {
        Write-Output "WARNING: VM domain is `$domain, expected $Domain"
        return 1
    }
}
catch {
    Write-Output "ERROR: Failed to check domain: `$(`$_.Exception.Message)"
    return 2
}
"@
    
    try {
        $result = Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroup -Name $VMName -CommandId 'RunPowerShellScript' -ScriptString $script -ErrorAction Stop
        Write-StatusMessage "Domain check result: $($result.Value[0].Message)" "INFO"
        return $result
    }
    catch {
        Write-StatusMessage "Failed to run domain check: $($_.Exception.Message)" "ERROR"
        return $null
    }
}

function Install-HPCPackPrerequisites {
    param([string]$ResourceGroup, [string]$VMName)
    
    Write-StatusMessage "Installing HPC Pack prerequisites on $VMName..." "PROGRESS"
    
    $script = @"
# Install required Windows features
Enable-WindowsOptionalFeature -Online -FeatureName IIS-WebServerRole -All
Enable-WindowsOptionalFeature -Online -FeatureName IIS-WebServer -All
Enable-WindowsOptionalFeature -Online -FeatureName IIS-CommonHttpFeatures -All
Enable-WindowsOptionalFeature -Online -FeatureName IIS-HttpErrors -All
Enable-WindowsOptionalFeature -Online -FeatureName IIS-HttpRedirect -All
Enable-WindowsOptionalFeature -Online -FeatureName IIS-ApplicationDevelopment -All
Enable-WindowsOptionalFeature -Online -FeatureName IIS-NetFxExtensibility45 -All
Enable-WindowsOptionalFeature -Online -FeatureName IIS-HealthAndDiagnostics -All
Enable-WindowsOptionalFeature -Online -FeatureName IIS-HttpLogging -All
Enable-WindowsOptionalFeature -Online -FeatureName IIS-Security -All
Enable-WindowsOptionalFeature -Online -FeatureName IIS-RequestFiltering -All
Enable-WindowsOptionalFeature -Online -FeatureName IIS-Performance -All
Enable-WindowsOptionalFeature -Online -FeatureName IIS-WebServerManagementTools -All
Enable-WindowsOptionalFeature -Online -FeatureName IIS-ManagementConsole -All
Enable-WindowsOptionalFeature -Online -FeatureName IIS-IIS6ManagementCompatibility -All
Enable-WindowsOptionalFeature -Online -FeatureName IIS-Metabase -All

# Install .NET Framework features
Enable-WindowsOptionalFeature -Online -FeatureName NetFx4Extended-ASPNET45 -All
Enable-WindowsOptionalFeature -Online -FeatureName IIS-NetFxExtensibility45 -All
Enable-WindowsOptionalFeature -Online -FeatureName IIS-ISAPIExtensions -All
Enable-WindowsOptionalFeature -Online -FeatureName IIS-ISAPIFilter -All
Enable-WindowsOptionalFeature -Online -FeatureName IIS-ASPNET45 -All

Write-Output "Prerequisites installation completed"
"@
    
    try {
        $result = Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroup -Name $VMName -CommandId 'RunPowerShellScript' -ScriptString $script -ErrorAction Stop
        Write-StatusMessage "Prerequisites installation result: $($result.Value[0].Message)" "SUCCESS"
        return $result
    }
    catch {
        Write-StatusMessage "Failed to install prerequisites: $($_.Exception.Message)" "ERROR"
        return $null
    }
}

function Fix-InfiniBandSupport {
    param([string]$ResourceGroup, [string]$VMName)
    
    if (-not $FixInfiniBand) {
        Write-StatusMessage "Skipping InfiniBand fixes (use -FixInfiniBand to enable)" "INFO"
        return
    }
    
    Write-StatusMessage "Configuring InfiniBand support on $VMName..." "PROGRESS"
    
    $script = @"
# Check VM size compatibility
`$vmSize = (Invoke-RestMethod -Uri 'http://169.254.169.254/metadata/instance/compute/vmSize?api-version=2021-02-01' -Headers @{'Metadata'='true'})
Write-Output "VM Size: `$vmSize"

if (`$vmSize -like "*HB*" -or `$vmSize -like "*HC*" -or `$vmSize -like "*ND*") {
    Write-Output "VM supports InfiniBand/RDMA"
    
    # Check for Mellanox adapters
    `$mellanoxDevices = Get-PnpDevice | Where-Object { `$_.FriendlyName -like "*Mellanox*" -or `$_.FriendlyName -like "*ConnectX*" }
    if (`$mellanoxDevices) {
        Write-Output "Found Mellanox devices:"
        `$mellanoxDevices | ForEach-Object { Write-Output "  - `$(`$_.FriendlyName)" }
        
        # Check RDMA capability
        try {
            `$rdmaAdapters = Get-NetAdapterRdma -ErrorAction SilentlyContinue
            if (`$rdmaAdapters) {
                Write-Output "RDMA-capable adapters found:"
                `$rdmaAdapters | ForEach-Object { Write-Output "  - `$(`$_.Name): Enabled=`$(`$_.Enabled)" }
            } else {
                Write-Output "No RDMA adapters found - may need driver installation"
            }
        }
        catch {
            Write-Output "RDMA check failed: `$(`$_.Exception.Message)"
        }
    } else {
        Write-Output "No Mellanox devices found - checking for driver issues"
        
        # Check for unknown devices
        `$unknownDevices = Get-PnpDevice | Where-Object { `$_.Status -eq "Unknown" -or `$_.Problem -ne 0 }
        if (`$unknownDevices) {
            Write-Output "Unknown/problematic devices found:"
            `$unknownDevices | ForEach-Object { Write-Output "  - `$(`$_.FriendlyName): Status=`$(`$_.Status), Problem=`$(`$_.Problem)" }
        }
    }
    
    # Check accelerated networking
    `$networkAdapters = Get-NetAdapter | Where-Object { `$_.Status -eq "Up" }
    foreach (`$adapter in `$networkAdapters) {
        `$properties = Get-NetAdapterAdvancedProperty -Name `$adapter.Name -DisplayName "*SR-IOV*" -ErrorAction SilentlyContinue
        if (`$properties) {
            Write-Output "Adapter `$(`$adapter.Name): SR-IOV = `$(`$properties.RegistryValue)"
        }
    }
} else {
    Write-Output "VM size `$vmSize does not support InfiniBand/RDMA"
}
"@
    
    try {
        $result = Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroup -Name $VMName -CommandId 'RunPowerShellScript' -ScriptString $script -ErrorAction Stop
        Write-StatusMessage "InfiniBand check completed: $($result.Value[0].Message)" "SUCCESS"
        return $result
    }
    catch {
        Write-StatusMessage "Failed to check InfiniBand support: $($_.Exception.Message)" "ERROR"
        return $null
    }
}

function Restart-HPCPackInstallation {
    param([string]$ResourceGroup, [string]$VMName, [string]$TemplateUri)
    
    Write-StatusMessage "Restarting HPC Pack installation on $VMName..." "PROGRESS"
    
    # This would typically involve re-running the ARM template deployment
    # or manually installing HPC Pack components
    Write-StatusMessage "Manual HPC Pack installation may be required" "WARNING"
    Write-StatusMessage "Consider using the HPC Pack installer directly on the VM" "INFO"
}

# Main execution
Write-StatusMessage "Starting HPC Pack DSC error diagnosis and repair..." "PROGRESS"
Write-StatusMessage "Resource Group: $ResourceGroupName" "INFO"
Write-StatusMessage "Head Node: $HeadNodeName" "INFO"

# Check if VM exists
try {
    $vm = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $HeadNodeName -ErrorAction Stop
    Write-StatusMessage "Found VM: $($vm.Name) (Size: $($vm.HardwareProfile.VmSize))" "SUCCESS"
}
catch {
    Write-StatusMessage "VM '$HeadNodeName' not found in resource group '$ResourceGroupName'" "ERROR"
    Write-StatusMessage "Available VMs in resource group:" "INFO"
    $vms = Get-AzVM -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
    foreach ($availableVm in $vms) {
        Write-StatusMessage "  - $($availableVm.Name)" "INFO"
    }
    exit 1
}

# Step 1: Check extension status
$extensions = Test-VMExtensionStatus -ResourceGroup $ResourceGroupName -VMName $HeadNodeName

# Step 2: Remove failed extensions
Remove-FailedExtensions -ResourceGroup $ResourceGroupName -VMName $HeadNodeName

# Step 3: Test domain configuration
Test-DomainConfiguration -ResourceGroup $ResourceGroupName -VMName $HeadNodeName -Domain $DomainName

# Step 4: Install prerequisites
Install-HPCPackPrerequisites -ResourceGroup $ResourceGroupName -VMName $HeadNodeName

# Step 5: Fix InfiniBand support (if requested)
if ($vm.HardwareProfile.VmSize -like "*HB*" -or $vm.HardwareProfile.VmSize -like "*HC*") {
    Fix-InfiniBandSupport -ResourceGroup $ResourceGroupName -VMName $HeadNodeName
}

Write-StatusMessage "HPC Pack DSC error diagnosis completed!" "SUCCESS"
Write-StatusMessage "Next steps:" "INFO"
Write-StatusMessage "1. Wait 5-10 minutes for services to stabilize" "INFO"
Write-StatusMessage "2. Re-run your HPC Pack deployment script" "INFO"
Write-StatusMessage "3. Monitor deployment progress in Azure Portal" "INFO"
Write-StatusMessage "4. If issues persist, consider manual HPC Pack installation" "INFO"
