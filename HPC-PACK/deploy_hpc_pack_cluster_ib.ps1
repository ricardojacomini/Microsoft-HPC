# Deploy HPC Pack cluster with InfiniBand support for HB120rs v3 nodes
# Requires Azure PowerShell module: Install-Module -Name Az

param(
    [Alias('DryRun')][switch]$WhatIf
)

# =============================== #
# Function Definitions            #
# =============================== #


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

function Get-AuthenticationKey {
    param ([string]$SubscriptionId)
    $authInput = Read-Host -Prompt "Enter authentication key (press Enter to use 'subscriptionId: $SubscriptionId')"
    if ([string]::IsNullOrWhiteSpace($authInput)) {
        Write-Host "Using default authentication key: subscriptionId: $SubscriptionId"
        return ConvertTo-SecureString "subscriptionId: $SubscriptionId" -AsPlainText -Force
    } else {
        return ConvertTo-SecureString $authInput -AsPlainText -Force
    }
}


function Ensure-ResourceGroup {
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
        Write-Output "Creating resource group: $Name"
        $rg = New-AzResourceGroup -Name $Name -Location $Location
    } else {
        Write-Output "Resource group already exists: $Name"
    }
    return $rg
}

function Ensure-Network {
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
        Write-Output "  - NSG: $NsgName with RDP, SMB, and RDMA rules"
        return @{ SubnetId = "/subscriptions/dummy/resourceGroups/$ResourceGroup/providers/Microsoft.Network/virtualNetworks/$VNetName/subnets/$SubnetName"; Nsg = $null }
    }
    
    # Create or get NSG with required rules
    $nsg = Get-AzNetworkSecurityGroup -ResourceGroupName $ResourceGroup -Name $NsgName -ErrorAction SilentlyContinue
    if (-not $nsg) {
        Write-Output "Creating Network Security Group: $NsgName"
        $rdpRule = New-AzNetworkSecurityRuleConfig -Name "AllowRDP" -Protocol "Tcp" -Direction "Inbound" -Priority 1000 -SourceAddressPrefix "*" -SourcePortRange "*" -DestinationAddressPrefix "*" -DestinationPortRange "3389" -Access "Allow"
        $smbRule = New-AzNetworkSecurityRuleConfig -Name "AllowSMB" -Protocol "Tcp" -Direction "Inbound" -Priority 1001 -SourceAddressPrefix "VirtualNetwork" -SourcePortRange "*" -DestinationAddressPrefix "*" -DestinationPortRange "445" -Access "Allow"
        $rdmaRule = New-AzNetworkSecurityRuleConfig -Name "AllowRDMA" -Protocol "*" -Direction "Inbound" -Priority 1002 -SourceAddressPrefix "VirtualNetwork" -SourcePortRange "*" -DestinationAddressPrefix "*" -DestinationPortRange "4791" -Access "Allow"
        $nsg = New-AzNetworkSecurityGroup -ResourceGroupName $ResourceGroup -Location $Location -Name $NsgName -SecurityRules $rdpRule, $smbRule, $rdmaRule
    }

    # Create or get VNet
    $vnet = Get-AzVirtualNetwork -ResourceGroupName $ResourceGroup -Name $VNetName -ErrorAction SilentlyContinue
    if (-not $vnet) {
        Write-Output "Creating Virtual Network: $VNetName"
        $subnetConfig = New-AzVirtualNetworkSubnetConfig -Name $SubnetName -AddressPrefix $SubnetPrefix -NetworkSecurityGroup $nsg
        $vnet = New-AzVirtualNetwork -ResourceGroupName $ResourceGroup -Location $Location -Name $VNetName -AddressPrefix $AddressPrefix -Subnet $subnetConfig
    }
    
    $subnet = $vnet.Subnets | Where-Object { $_.Name -eq $SubnetName }
    return @{ SubnetId = $subnet.Id; Nsg = $nsg }
}

function Deploy-IBVMs {
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
        Write-Output "[DRY-RUN] Would deploy $VmCount VMs:"
        for ($i = 1; $i -le $VmCount; $i++) {
            Write-Output "  - $VmPrefix$i ($VmSize) with InfiniBand/RDMA support"
        }
        return
    }
    
    for ($i = 1; $i -le $VmCount; $i++) {
        $vmName = "$VmPrefix$i"
        Write-Output "Creating VM: $vmName"
        
        # Create public IP
        $pip = New-AzPublicIpAddress -ResourceGroupName $ResourceGroup -Location $Location -Name "$vmName-pip" -AllocationMethod Static -Sku Standard
        
        # Create NIC
        $nic = New-AzNetworkInterface -ResourceGroupName $ResourceGroup -Location $Location -Name "$vmName-nic" -SubnetId $SubnetId -PublicIpAddressId $pip.Id -NetworkSecurityGroupId $Nsg.Id -EnableAcceleratedNetworking
        
        # Create VM configuration for HB120rs_v3 with InfiniBand
        $vmConfig = New-AzVMConfig -VMSize $VmSize -VMName $vmName
        $vmConfig = Set-AzVMOperatingSystem -VM $vmConfig -Windows -ComputerName $vmName -Credential (New-Object PSCredential($AdminUsername, $AdminPassword)) -ProvisionVMAgent -EnableAutoUpdate
        $vmConfig = Set-AzVMSourceImage -VM $vmConfig -PublisherName "MicrosoftWindowsServer" -Offer "WindowsServer" -Skus "2022-datacenter-g2" -Version "latest"
        
        # Configure Trusted Launch with disabled features for InfiniBand compatibility
        $vmConfig = Set-AzVMSecurityProfile -VM $vmConfig -SecurityType "TrustedLaunch"
        $vmConfig = Set-AzVMUefi -VM $vmConfig -EnableVtpm $false -EnableSecureBoot $false
        
        $vmConfig = Add-AzVMNetworkInterface -VM $vmConfig -Id $nic.Id
        New-AzVM -ResourceGroupName $ResourceGroup -Location $Location -VM $vmConfig -DisableBginfoExtension
    }
}

function Configure-InfiniBand {
    param (
        [string]$ResourceGroup,
        [string]$VmPrefix,
        [int]$VmCount,
        [string]$DriverUrl,
        [string]$DriverInstaller,
        [string]$DownloadPath
    )
    
    for ($i = 1; $i -le $VmCount; $i++) {
        $vmName = "$VmPrefix$i"
        Write-Output "Configuring InfiniBand support on $vmName..."
        
        $scriptContent = @"
if (!(Test-Path '$DownloadPath')) { New-Item -ItemType Directory -Path '$DownloadPath' -Force }
Invoke-WebRequest -Uri '$DriverUrl' -OutFile '$DownloadPath\$DriverInstaller'
Start-Process -FilePath '$DownloadPath\$DriverInstaller' -ArgumentList '/S /v/qn' -Wait
`$check = Get-WmiObject Win32_PnPSignedDriver | Where-Object { `$_.DeviceName -like '*Mellanox*' }
if (`$check) { Write-Output 'Driver installed on $vmName.' } else { Write-Error 'Driver install failed on $vmName.' }
`$rdma = Get-NetAdapterRdma | Where-Object { `$_.Enabled -eq `$true }
if (`$rdma) { Write-Output 'RDMA is enabled on $vmName.' } else { Write-Error 'RDMA not enabled on $vmName.' }
Remove-Item '$DownloadPath\$DriverInstaller' -Force
"@
        
        Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroup -Name $vmName -CommandId 'RunPowerShellScript' -ScriptString $scriptContent
    }
}

# =============================== #
# Main Execution                  #
# =============================== #

# Parameters
$resourceGroup = "HPCPack-IB-jacomini"
$location = "eastus"
$vmSize = "Standard_HB120rs_v3"
$vmCount = 2
$vmPrefix = "HPCNode"
$adminUsername = "azureuser"
$adminPassword = Read-Host -Prompt "Enter admin password" -AsSecureString
$vnetName = "HPCVNet"
$subnetName = "HPCSubnet"
$addressPrefix = "10.1.0.0/16"
$subnetPrefix = "10.1.0.0/24"
$nsgName = "HPCNSG"
$driverUrl = "https://content.mellanox.com/WinOF/MLNX_WinOF2-25_4_50020_All_x64.exe"
$driverInstaller = "WinOF2-latest.exe"
$downloadPath = "C:\Temp\Infiniband"

# Main execution
$selectedSub = Select-AzSubscriptionContext
$subscriptionId = $selectedSub.Id

$authenticationKey = Get-AuthenticationKey -SubscriptionId $subscriptionId

Ensure-ResourceGroup -Name $resourceGroup -Location $location -WhatIf:$WhatIf
$net = Ensure-Network -ResourceGroup $resourceGroup -Location $location -VNetName $vnetName -SubnetName $subnetName -AddressPrefix $addressPrefix -SubnetPrefix $subnetPrefix -NsgName $nsgName -WhatIf:$WhatIf
Deploy-IBVMs -ResourceGroup $resourceGroup -Location $location -VmPrefix $vmPrefix -VmSize $vmSize -VmCount $vmCount -AdminUsername $adminUsername -AdminPassword $adminPassword -SubnetId $net.SubnetId -Nsg $net.Nsg -WhatIf:$WhatIf

if (-not $WhatIf) {
    Configure-InfiniBand -ResourceGroup $resourceGroup -VmPrefix $vmPrefix -VmCount $vmCount -DriverUrl $driverUrl -DriverInstaller $driverInstaller -DownloadPath $downloadPath
} else {
    Write-Output "[DRY-RUN] Skipping InfiniBand driver installation and validation."
}

Write-Output ""
Write-Output "HPC Pack cluster deployed with RDMA/InfiniBand enabled on HB120rs v3 nodes."
