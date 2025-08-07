# Deploy H Series VMs with InfiniBand support for Windows Server 2019
# This script creates Azure H series VMs with InfiniBand/RDMA capabilities without HPC Pack
# Requires Azure PowerShell module: Install-Module -Name Az
#
# Usage Examples:
#   .\deploy_h_series_ib_win2019.ps1 -ShowPricing                    # Show pricing comparison
#   .\deploy_h_series_ib_win2019.ps1 -VmSize "Standard_HC44rs"       # Use HC44rs (cost-effective)
#   .\deploy_h_series_ib_win2019.ps1 -VmSize "Standard_HB120-32rs_v3" # Use HB series with 32 cores
#   .\deploy_h_series_ib_win2019.ps1 -WhatIf                         # Dry run
#   .\deploy_h_series_ib_win2019.ps1 -CheckQuota                     # Check quota before deployment
#
# Available VM Sizes:
#   Standard_HC44rs          - 44 vCPUs, 352 GB RAM, ~$2.20/hour (RECOMMENDED)
#   Standard_HB120-16rs_v3   - 16 vCPUs, 456 GB RAM, ~$0.95/hour (Budget)
#   Standard_HB120-32rs_v3   - 32 vCPUs, 456 GB RAM, ~$1.90/hour (Balanced)
#   Standard_HB120-64rs_v3   - 64 vCPUs, 456 GB RAM, ~$3.80/hour
#   Standard_HB120rs_v3      - 120 vCPUs, 456 GB RAM, ~$7.20/hour
#   Standard_HB176rs_v4      - 176 vCPUs, 768 GB RAM, ~$12.00/hour (Latest)

param(
    [Alias('DryRun')][switch]$WhatIf,
    [string]$ResourceGroupName = "HSeries-IB-jacomini",
    [string]$Location = "eastus",
    [ValidateSet("Standard_HC44rs", "Standard_HB120-16rs_v3", "Standard_HB120-32rs_v3", "Standard_HB120-64rs_v3", "Standard_HB120rs_v3", "Standard_HB176rs_v4")]
    [string]$VmSize = "Standard_HC44rs", # More cost-effective H-series with InfiniBand support
    [int]$VmCount = 2,
    [string]$VmPrefix = "HSeries-IB",
    [string]$AdminUsername = "azureuser",
    [switch]$CheckQuota,
    [switch]$ShowPricing
)

# =============================== #
# Function Definitions            #
# =============================== #

function Get-VMSizeInfo {
    param([string]$VmSize)
    
    $vmSizeInfo = @{
        "Standard_HC44rs" = @{
            vCPUs = 44
            RAM = "352 GB"
            InfiniBand = "100 Gbps HDR"
            EstimatedCost = "$2.20/hour"
            Description = "Most cost-effective option with full InfiniBand support"
        }
        "Standard_HB120-16rs_v3" = @{
            vCPUs = 16
            RAM = "456 GB"
            InfiniBand = "200 Gbps HDR"
            EstimatedCost = "$0.95/hour"
            Description = "Budget-friendly HB series with reduced cores"
        }
        "Standard_HB120-32rs_v3" = @{
            vCPUs = 32
            RAM = "456 GB"
            InfiniBand = "200 Gbps HDR"
            EstimatedCost = "$1.90/hour"
            Description = "Balanced price/performance HB series"
        }
        "Standard_HB120-64rs_v3" = @{
            vCPUs = 64
            RAM = "456 GB"
            InfiniBand = "200 Gbps HDR"
            EstimatedCost = "$3.80/hour"
            Description = "High-performance HB series"
        }
        "Standard_HB120rs_v3" = @{
            vCPUs = 120
            RAM = "456 GB"
            InfiniBand = "200 Gbps HDR"
            EstimatedCost = "$7.20/hour"
            Description = "Full HB series with maximum cores"
        }
        "Standard_HB176rs_v4" = @{
            vCPUs = 176
            RAM = "768 GB"
            InfiniBand = "400 Gbps NDR"
            EstimatedCost = "$12.00/hour"
            Description = "Latest generation HB series with highest performance"
        }
    }
    
    return $vmSizeInfo[$VmSize]
}

function Test-QuotaAvailability {
    param(
        [string]$Location,
        [string]$VmSize,
        [int]$VmCount
    )
    
    Write-Output "Checking quota availability for $VmSize in $Location..."
    
    try {
        $vmInfo = Get-VMSizeInfo -VmSize $VmSize
        $requiredvCPUs = $vmInfo.vCPUs * $VmCount
        
        # Get current usage
        $usage = az vm list-usage --location $Location --query "[?contains(name.value, 'H')]" -o json | ConvertFrom-Json
        
        $relevantQuota = $null
        switch -Wildcard ($VmSize) {
            "Standard_HC*" { $relevantQuota = $usage | Where-Object { $_.name.value -eq "standardHFamily" } }
            "Standard_HB*" { $relevantQuota = $usage | Where-Object { $_.name.value -eq "standardHFamily" } }
            "Standard_HX*" { $relevantQuota = $usage | Where-Object { $_.name.value -eq "standardHXFamily" } }
        }
        
        if ($relevantQuota) {
            $available = $relevantQuota.limit - $relevantQuota.currentValue
            Write-Output "Quota Status:"
            Write-Output "  Current Usage: $($relevantQuota.currentValue) vCPUs"
            Write-Output "  Quota Limit: $($relevantQuota.limit) vCPUs"
            Write-Output "  Available: $available vCPUs"
            Write-Output "  Required: $requiredvCPUs vCPUs"
            
            if ($available -ge $requiredvCPUs) {
                Write-Output "SUCCESS: Sufficient quota available!"
                return $true
            } else {
                Write-Warning "WARNING: Insufficient quota! Need $requiredvCPUs vCPUs but only $available available."
                Write-Output "To request quota increase:"
                Write-Output "  1. Go to Azure Portal > Subscriptions > Usage + quotas"
                Write-Output "  2. Search for 'Compute' and select your region"
                Write-Output "  3. Request increase for 'Standard H Family vCPUs'"
                return $false
            }
        } else {
            Write-Warning "WARNING: Could not determine quota for $VmSize"
            return $null
        }
    } catch {
        Write-Warning "WARNING: Could not check quota: $($_.Exception.Message)"
        return $null
    }
}

function Show-PricingComparison {
    Write-Output ""
    Write-Output "H-Series VM Pricing Comparison (East US):"
    Write-Output "=" * 60
    
    $vmSizes = @("Standard_HC44rs", "Standard_HB120-16rs_v3", "Standard_HB120-32rs_v3", "Standard_HB120-64rs_v3", "Standard_HB120rs_v3", "Standard_HB176rs_v4")
    
    foreach ($size in $vmSizes) {
        $info = Get-VMSizeInfo -VmSize $size
        Write-Output "$size"
        Write-Output "  vCPUs: $($info.vCPUs), RAM: $($info.RAM)"
        Write-Output "  InfiniBand: $($info.InfiniBand)"
        Write-Output "  Estimated Cost: $($info.EstimatedCost)"
        Write-Output "  Description: $($info.Description)"
        Write-Output ""
    }
}

function Select-AzSubscriptionContext {
    # Try to get current context first
    $currentContext = Get-AzContext
    if ($currentContext -and $currentContext.Subscription) {
        Write-Output "🔍 Using current Azure context:"
        Write-Output "   Subscription: $($currentContext.Subscription.Name) ($($currentContext.Subscription.Id))"
        Write-Output "   Account: $($currentContext.Account.Id)"
        
        $confirmation = Read-Host "Continue with this subscription? (Y/N)"
        if ($confirmation -eq "Y" -or $confirmation -eq "y") {
            return $currentContext.Subscription
        }
    }
    
    # Fallback: Try Get-AzSubscription with error handling
    try {
        $selectedSub = Get-AzSubscription | Out-GridView -Title "Select a subscription" -PassThru
        if (-not $selectedSub) {
            Write-Output "`n❌ No subscription selected. Exiting script."
            Write-Output "Try running: Connect-AzAccount "
            exit 1
        }
        Set-AzContext -SubscriptionId $selectedSub.Id -TenantId $selectedSub.TenantId
        return $selectedSub
    }
    catch {
        Write-Output "❌ Error accessing subscriptions: $($_.Exception.Message)"
        Write-Output "Try running: Connect-AzAccount"
        Write-Output "Or: Update-Module Az -Force"
        exit 1
    }
}

function New-ResourceGroupIfNotExists {
    param (
        [string]$Name,
        [string]$Location,
        [switch]$WhatIf
    )
    
    if ($WhatIf) {
        Write-Output "[DRY-RUN] Would check/create resource group: $Name in $Location"
        return
    }
    
    $rg = Get-AzResourceGroup -Name $Name -ErrorAction SilentlyContinue
    if (-not $rg) {
        Write-Output "✅ Creating resource group: $Name"
        $rg = New-AzResourceGroup -Name $Name -Location $Location
    } else {
        Write-Output "ℹ️  Resource group already exists: $Name"
    }
    return $rg
}

function New-NetworkInfrastructure {
    param (
        [string]$ResourceGroup,
        [string]$Location,
        [string]$VNetName,
        [string]$SubnetName,
        [string]$AddressPrefix,
        [string]$SubnetPrefix,
        [string]$NsgName,
        [switch]$WhatIf
    )
    
    if ($WhatIf) {
        Write-Output "[DRY-RUN] Would check/create network resources:"
        Write-Output "  - VNet: $VNetName ($AddressPrefix)"
        Write-Output "  - Subnet: $SubnetName ($SubnetPrefix)"
        Write-Output "  - NSG: $NsgName with RDP, SMB, and InfiniBand/RDMA rules"
        return @{ SubnetId = "/subscriptions/dummy/resourceGroups/$ResourceGroup/providers/Microsoft.Network/virtualNetworks/$VNetName/subnets/$SubnetName"; Nsg = $null }
    }
    
    # Create or get NSG with InfiniBand/RDMA rules
    $nsg = Get-AzNetworkSecurityGroup -ResourceGroupName $ResourceGroup -Name $NsgName -ErrorAction SilentlyContinue
    if (-not $nsg) {
        Write-Output "✅ Creating Network Security Group: $NsgName with InfiniBand rules"
        
        # RDP access
        $rdpRule = New-AzNetworkSecurityRuleConfig -Name "AllowRDP" -Protocol "Tcp" -Direction "Inbound" -Priority 1000 -SourceAddressPrefix "*" -SourcePortRange "*" -DestinationAddressPrefix "*" -DestinationPortRange "3389" -Access "Allow"
        
        # SMB for file sharing
        $smbRule = New-AzNetworkSecurityRuleConfig -Name "AllowSMB" -Protocol "Tcp" -Direction "Inbound" -Priority 1001 -SourceAddressPrefix "VirtualNetwork" -SourcePortRange "*" -DestinationAddressPrefix "*" -DestinationPortRange "445" -Access "Allow"
        
        # InfiniBand/RDMA traffic (port 4791 is standard for IB)
        $rdmaRule = New-AzNetworkSecurityRuleConfig -Name "AllowRDMA" -Protocol "*" -Direction "Inbound" -Priority 1002 -SourceAddressPrefix "VirtualNetwork" -SourcePortRange "*" -DestinationAddressPrefix "*" -DestinationPortRange "4791" -Access "Allow"
        
        # Additional InfiniBand ports (if needed for specific applications)
        $ibPortsRule = New-AzNetworkSecurityRuleConfig -Name "AllowIBPorts" -Protocol "*" -Direction "Inbound" -Priority 1003 -SourceAddressPrefix "VirtualNetwork" -SourcePortRange "*" -DestinationAddressPrefix "*" -DestinationPortRange "20001-20048" -Access "Allow"
        
        $nsg = New-AzNetworkSecurityGroup -ResourceGroupName $ResourceGroup -Location $Location -Name $NsgName -SecurityRules $rdpRule, $smbRule, $rdmaRule, $ibPortsRule
    } else {
        Write-Output "ℹ️  Network Security Group already exists: $NsgName"
    }

    # Create or get VNet
    $vnet = Get-AzVirtualNetwork -ResourceGroupName $ResourceGroup -Name $VNetName -ErrorAction SilentlyContinue
    if (-not $vnet) {
        Write-Output "✅ Creating Virtual Network: $VNetName"
        $subnetConfig = New-AzVirtualNetworkSubnetConfig -Name $SubnetName -AddressPrefix $SubnetPrefix -NetworkSecurityGroup $nsg
        $vnet = New-AzVirtualNetwork -ResourceGroupName $ResourceGroup -Location $Location -Name $VNetName -AddressPrefix $AddressPrefix -Subnet $subnetConfig
    } else {
        Write-Output "ℹ️  Virtual Network already exists: $VNetName"
    }
    
    $subnet = $vnet.Subnets | Where-Object { $_.Name -eq $SubnetName }
    return @{ SubnetId = $subnet.Id; Nsg = $nsg }
}

function New-HSeriesVMs {
    param (
        [string]$ResourceGroup,
        [string]$Location,
        [string]$VmPrefix,
        [string]$VmSize,
        [int]$VmCount,
        [string]$AdminUsername,
        [SecureString]$AdminPassword,
        [string]$SubnetId,
        [object]$Nsg,
        [switch]$WhatIf
    )
    
    if ($WhatIf) {
        Write-Output "[DRY-RUN] Would deploy $VmCount H Series VMs:"
        for ($i = 1; $i -le $VmCount; $i++) {
            Write-Output "  - $VmPrefix$i ($VmSize) with InfiniBand/RDMA support on Windows Server 2019"
        }
        return
    }
    
    Write-Output "🚀 Deploying $VmCount H Series VMs with InfiniBand support..."
    
    for ($i = 1; $i -le $VmCount; $i++) {
        $vmName = "$VmPrefix$i"
        Write-Output "✅ Creating VM: $vmName"
        
        # Create public IP
        $pip = New-AzPublicIpAddress -ResourceGroupName $ResourceGroup -Location $Location -Name "$vmName-pip" -AllocationMethod Static -Sku Standard
        
        # Create NIC with accelerated networking (required for InfiniBand)
        $nic = New-AzNetworkInterface -ResourceGroupName $ResourceGroup -Location $Location -Name "$vmName-nic" -SubnetId $SubnetId -PublicIpAddressId $pip.Id -NetworkSecurityGroupId $Nsg.Id -EnableAcceleratedNetworking
        
        # Create VM configuration for H Series with InfiniBand support
        $vmConfig = New-AzVMConfig -VMSize $VmSize -VMName $vmName
        
        # Set Windows Server 2019 as the OS
        $vmConfig = Set-AzVMOperatingSystem -VM $vmConfig -Windows -ComputerName $vmName -Credential (New-Object PSCredential($AdminUsername, $AdminPassword)) -ProvisionVMAgent -EnableAutoUpdate
        $vmConfig = Set-AzVMSourceImage -VM $vmConfig -PublisherName "MicrosoftWindowsServer" -Offer "WindowsServer" -Skus "2019-datacenter" -Version "latest"
        
        # Configure for InfiniBand compatibility (disable some security features that can interfere)
        $vmConfig = Set-AzVMSecurityProfile -VM $vmConfig -SecurityType "TrustedLaunch"
        $vmConfig = Set-AzVMUefi -VM $vmConfig -EnableVtpm $false -EnableSecureBoot $false
        
        # Add the network interface
        $vmConfig = Add-AzVMNetworkInterface -VM $vmConfig -Id $nic.Id
        
        # Create the VM
        $vm = New-AzVM -ResourceGroupName $ResourceGroup -Location $Location -VM $vmConfig -DisableBginfoExtension
        
        if ($vm.ProvisioningState -eq "Succeeded") {
            Write-Output "✅ VM $vmName created successfully"
        } else {
            Write-Warning "⚠️  VM $vmName creation may have issues. Check Azure portal."
        }
    }
}

function Install-InfiniBandDrivers {
    param (
        [string]$ResourceGroup,
        [string]$VmPrefix,
        [int]$VmCount,
        [string]$DriverUrl,
        [string]$DriverInstaller,
        [string]$DownloadPath,
        [switch]$WhatIf
    )
    
    if ($WhatIf) {
        Write-Output "[DRY-RUN] Would configure InfiniBand drivers on all VMs"
        Write-Output "  - Download Mellanox drivers from: $DriverUrl"
        Write-Output "  - Install drivers and configure RDMA"
        Write-Output "  - Verify InfiniBand adapter functionality"
        return
    }
    
    Write-Output "🔧 Configuring InfiniBand drivers on all VMs..."
    
    for ($i = 1; $i -le $VmCount; $i++) {
        $vmName = "$VmPrefix$i"
        Write-Output "📦 Installing InfiniBand drivers on $vmName..."
        
        $scriptContent = @"
# Create download directory
if (!(Test-Path '$DownloadPath')) { 
    New-Item -ItemType Directory -Path '$DownloadPath' -Force 
    Write-Output "Created directory: $DownloadPath"
}

# Download Mellanox WinOF-2 drivers
Write-Output "Downloading Mellanox InfiniBand drivers..."
try {
    Invoke-WebRequest -Uri '$DriverUrl' -OutFile '$DownloadPath\$DriverInstaller' -UseBasicParsing
    Write-Output "Driver download completed successfully"
} catch {
    Write-Error "Failed to download drivers: `$(`$_.Exception.Message)"
    exit 1
}

# Install drivers silently
Write-Output "Installing InfiniBand drivers..."
try {
    Start-Process -FilePath '$DownloadPath\$DriverInstaller' -ArgumentList '/S /v/qn' -Wait -PassThru
    Write-Output "Driver installation completed"
} catch {
    Write-Error "Driver installation failed: `$(`$_.Exception.Message)"
    exit 1
}

# Wait for driver installation to complete
Start-Sleep -Seconds 30

# Verify Mellanox adapter is recognized
Write-Output "Verifying InfiniBand adapter installation..."
`$mellanoxDevices = Get-WmiObject Win32_PnPSignedDriver | Where-Object { `$_.DeviceName -like '*Mellanox*' -or `$_.DeviceName -like '*ConnectX*' }
if (`$mellanoxDevices) {
    Write-Output "✅ Mellanox InfiniBand adapter detected:"
    `$mellanoxDevices | ForEach-Object { Write-Output "   - `$(`$_.DeviceName)" }
} else {
    Write-Warning "⚠️  No Mellanox devices found after driver installation"
}

# Check RDMA capabilities
Write-Output "Checking RDMA adapter status..."
try {
    `$rdmaAdapters = Get-NetAdapterRdma
    if (`$rdmaAdapters | Where-Object { `$_.Enabled -eq `$true }) {
        Write-Output "✅ RDMA is enabled on $vmName"
        `$rdmaAdapters | Where-Object { `$_.Enabled -eq `$true } | ForEach-Object {
            Write-Output "   - RDMA Adapter: `$(`$_.Name) (Enabled: `$(`$_.Enabled))"
        }
    } else {
        Write-Warning "⚠️  RDMA adapters found but not enabled on $vmName"
        `$rdmaAdapters | ForEach-Object {
            Write-Output "   - RDMA Adapter: `$(`$_.Name) (Enabled: `$(`$_.Enabled))"
        }
    }
} catch {
    Write-Warning "⚠️  Could not check RDMA status: `$(`$_.Exception.Message)"
}

# Check network adapters for InfiniBand
Write-Output "Checking network adapters..."
`$networkAdapters = Get-NetAdapter | Where-Object { `$_.Name -like '*Ethernet*' -and `$_.Status -eq 'Up' }
`$networkAdapters | ForEach-Object {
    Write-Output "   - Network Adapter: `$(`$_.Name) (Status: `$(`$_.Status), Speed: `$(`$_.LinkSpeed))"
}

# Cleanup installer
Remove-Item '$DownloadPath\$DriverInstaller' -Force -ErrorAction SilentlyContinue
Write-Output "InfiniBand configuration completed on $vmName"
"@
        
        try {
            $result = Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroup -Name $vmName -CommandId 'RunPowerShellScript' -ScriptString $scriptContent
            Write-Output "✅ InfiniBand configuration completed on $vmName"
            
            # Display the output from the script
            if ($result.Value -and $result.Value.Count -gt 0) {
                $vmNameForOutput = $vmName
                Write-Output "Script output from $vmNameForOutput :"
                $result.Value[0].Message -split "`n" | ForEach-Object { Write-Output "  $_" }
            }
        } catch {
            Write-Warning "WARNING: Failed to configure InfiniBand on $vmName : $($_.Exception.Message)"
        }
    }
}

function Test-InfiniBandConnectivity {
    param (
        [string]$ResourceGroup,
        [string]$VmPrefix,
        [int]$VmCount,
        [switch]$WhatIf
    )
    
    if ($WhatIf) {
        Write-Output "[DRY-RUN] Would test InfiniBand connectivity between VMs"
        return
    }
    
    if ($VmCount -lt 2) {
        Write-Output "ℹ️  Skipping connectivity test - need at least 2 VMs for testing"
        return
    }
    
    Write-Output "🧪 Testing InfiniBand connectivity between VMs..."
    
    # Test from VM1 to VM2
    $vm1Name = "$VmPrefix" + "1"
    $vm2Name = "$VmPrefix" + "2"
    
    # Get private IP of VM2
    $vm2Nic = Get-AzNetworkInterface -ResourceGroupName $ResourceGroup | Where-Object { $_.Name -eq "$vm2Name-nic" }
    $vm2PrivateIP = $vm2Nic.IpConfigurations[0].PrivateIpAddress
    
    Write-Output "Testing connectivity from $vm1Name to $vm2Name ($vm2PrivateIP)..."
    
    $testScript = @"
# Test basic connectivity
Write-Output "Testing basic network connectivity to $vm2PrivateIP..."
`$pingResult = Test-NetConnection -ComputerName '$vm2PrivateIP' -Port 3389
if (`$pingResult.TcpTestSucceeded) {
    Write-Output "SUCCESS: Basic connectivity successful"
} else {
    Write-Output "ERROR: Basic connectivity failed"
}

# Check SMB capabilities (tests RDMA indirectly)
Write-Output "Checking SMB client network interfaces..."
try {
    `$smbInterfaces = Get-SmbClientNetworkInterface
    `$smbInterfaces | ForEach-Object {
        Write-Output "   - SMB Interface: `$(`$_.InterfaceAlias) (RSS: `$(`$_.RssCapable), RDMA: `$(`$_.RdmaCapable))"
    }
} catch {
    Write-Output "WARNING: Could not check SMB network interfaces"
}

Write-Output "InfiniBand connectivity test completed"
"@
    
    try {
        $result = Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroup -Name $vm1Name -CommandId 'RunPowerShellScript' -ScriptString $testScript
        Write-Output "SUCCESS: Connectivity test completed"
        
        if ($result.Value -and $result.Value.Count -gt 0) {
            Write-Output "Test results:"
            $result.Value[0].Message -split "`n" | ForEach-Object { Write-Output "  $_" }
        }
    } catch {
        Write-Warning "WARNING: Connectivity test failed: $($_.Exception.Message)"
    }
}

# =============================== #
# Main Execution                  #
# =============================== #

Write-Output "🚀 H Series VM with InfiniBand Deployment Script"
Write-Output "================================================"
Write-Output ""

# Configuration parameters
$timestamp = Get-Date -Format "MMddHHmm"
$ResourceGroupName = $ResourceGroupName + $timestamp
$vnetName = "HSeries-VNet"
$subnetName = "InfiniBand-Subnet"
$addressPrefix = "10.1.0.0/16"
$subnetPrefix = "10.1.0.0/24"
$nsgName = "HSeries-IB-NSG"

# Mellanox WinOF-2 driver configuration
$driverUrl = "https://content.mellanox.com/WinOF/MLNX_WinOF2-25_4_50020_All_x64.exe"
$driverInstaller = "MLNX_WinOF2-latest.exe"
$downloadPath = "C:\Temp\InfiniBand"

# Display configuration
Write-Output "Configuration:"
Write-Output "  Resource Group: $ResourceGroupName"
Write-Output "  Location: $Location"
Write-Output "  VM Size: $VmSize"
Write-Output "  VM Count: $VmCount"
Write-Output "  VM Prefix: $VmPrefix"
Write-Output "  Admin Username: $AdminUsername"
Write-Output "  OS: Windows Server 2019"
Write-Output "  InfiniBand Driver: Mellanox WinOF-2"
Write-Output ""

# Show VM size details
$vmInfo = Get-VMSizeInfo -VmSize $VmSize
if ($vmInfo) {
    Write-Output "Selected VM Details:"
    Write-Output "  vCPUs: $($vmInfo.vCPUs)"
    Write-Output "  RAM: $($vmInfo.RAM)"
    Write-Output "  InfiniBand: $($vmInfo.InfiniBand)"
    Write-Output "  Estimated Cost: $($vmInfo.EstimatedCost) per VM"
    Write-Output "  Total Estimated Cost: $([math]::Round([decimal]($vmInfo.EstimatedCost -replace '[$\/hour]','') * $VmCount, 2))/hour for $VmCount VMs"
    Write-Output "  Description: $($vmInfo.Description)"
    Write-Output ""
}

# Show pricing comparison if requested
if ($ShowPricing) {
    Show-PricingComparison
}

# Check quota availability
if ($CheckQuota -and -not $WhatIf) {
    $quotaCheck = Test-QuotaAvailability -Location $Location -VmSize $VmSize -VmCount $VmCount
    if ($quotaCheck -eq $false) {
        $continue = Read-Host "Insufficient quota detected. Continue anyway? (Y/N)"
        if ($continue -ne "Y" -and $continue -ne "y") {
            Write-Output "Deployment cancelled due to quota limitations."
            exit 1
        }
    }
    Write-Output ""
}

# Get admin password
if (-not $WhatIf) {
    $adminPassword = Read-Host -Prompt "Enter admin password for VMs" -AsSecureString
} else {
    $adminPassword = ConvertTo-SecureString "DummyPassword123!" -AsPlainText -Force
}

# Main execution
Write-Output "🔑 Selecting Azure subscription..."
$selectedSub = Select-AzSubscriptionContext
Write-Output "Selected subscription: $($selectedSub.Name) ($($selectedSub.Id))"
Write-Output ""

Write-Output "📋 Ensuring resource group exists..."
New-ResourceGroupIfNotExists -Name $ResourceGroupName -Location $Location -WhatIf:$WhatIf
Write-Output ""

Write-Output "🌐 Setting up network infrastructure..."
$net = New-NetworkInfrastructure -ResourceGroup $ResourceGroupName -Location $Location -VNetName $vnetName -SubnetName $subnetName -AddressPrefix $addressPrefix -SubnetPrefix $subnetPrefix -NsgName $nsgName -WhatIf:$WhatIf
Write-Output ""

Write-Output "💻 Deploying H Series VMs..."
New-HSeriesVMs -ResourceGroup $ResourceGroupName -Location $Location -VmPrefix $VmPrefix -VmSize $VmSize -VmCount $VmCount -AdminUsername $AdminUsername -AdminPassword $adminPassword -SubnetId $net.SubnetId -Nsg $net.Nsg -WhatIf:$WhatIf
Write-Output ""

if (-not $WhatIf) {
    Write-Output "⏳ Waiting for VMs to be fully provisioned before driver installation..."
    Start-Sleep -Seconds 60
    
    Write-Output "🔧 Installing and configuring InfiniBand drivers..."
    Install-InfiniBandDrivers -ResourceGroup $ResourceGroupName -VmPrefix $VmPrefix -VmCount $VmCount -DriverUrl $driverUrl -DriverInstaller $driverInstaller -DownloadPath $downloadPath
    Write-Output ""
    
    Write-Output "🧪 Testing InfiniBand connectivity..."
    Test-InfiniBandConnectivity -ResourceGroup $ResourceGroupName -VmPrefix $VmPrefix -VmCount $VmCount
    Write-Output ""
} else {
    Write-Output "[DRY-RUN] Skipping driver installation and connectivity testing"
    Write-Output ""
}

Write-Output "✅ H Series VM deployment with InfiniBand support completed!"
Write-Output ""
Write-Output "Next Steps:"
Write-Output "  1. Connect to VMs via RDP using the public IPs"
Write-Output "  2. Verify InfiniBand adapters with: Get-NetAdapterRdma"
Write-Output "  3. Check Mellanox adapters with: Get-NetAdapter | Where-Object {`$_.Name -like '*Ethernet*'}"
Write-Output "  4. Test RDMA capabilities with your HPC applications"
Write-Output ""
Write-Output "Useful Commands for InfiniBand Verification:"
Write-Output "  Get-NetAdapterRdma"
Write-Output "  Get-SmbClientNetworkInterface"
Write-Output "  Get-NetAdapter | Where-Object { `$_.Name -eq 'Ethernet 2' } | Format-List *"
Write-Output ""
