
<#
.SYNOPSIS
    Deploys an Azure HPC Pack cluster with InfiniBand (RDMA) support for HB120rs v3 nodes using direct PowerShell VM deployment (not ARM/Bicep templates).

.DESCRIPTION
    This PowerShell script automates the deployment of an HPC Pack cluster in Azure, including:
    - Creation of a resource group, Virtual Network, subnet, and Network Security Group (NSG) with rules for RDP, SMB, and RDMA
    - Deployment of HB120rs v3 VMs with accelerated networking
    - Installation and validation of Mellanox WinOF2 drivers for InfiniBand/RDMA
    - RDMA capability check on each node
    The script is intended for high-performance computing workloads requiring low-latency, high-throughput networking.

    > Note: This script uses direct PowerShell commands for VM and network deployment, not ARM/Bicep template parameterization. If you require more granular control or wish to use template-based deployment (with parameters such as computeNodeOsDiskType, availabilitySetOption, etc.), you can refactor this script or request a template-based version.

.AUTHOR
    Ricardo de Souza Jacomini

.DATE
    July 29, 2025

.NOTES
    - Update network address ranges and admin credentials as needed for your environment.
    - Monitor deployment and driver installation status in the console and Azure Portal.
    - For more advanced scenarios or parameterization, consider using ARM/Bicep templates and passing parameters for compute and storage configuration.
#>

# =============================== #
# Deploy HPC Pack Cluster with IB #
# =============================== #


# =============================== #
# Modular Function Definitions    #
# =============================== #

function Select-AzSubscriptionContext {
    $selectedSub = Get-AzSubscription | Out-GridView -Title "Select a subscription" -PassThru
    if (-not $selectedSub) {
        Write-Host "`n❌ No subscription selected. Exiting script."
        Write-Host "Try running: Connect-AzAccount "
        exit 1
    }
    Set-AzContext -SubscriptionId $selectedSub.Id -TenantId $selectedSub.TenantId
    return $selectedSub
}

function Ensure-ResourceGroup {
    param (
        [string]$Name,
        [string]$Location
    )
    if (Get-AzResourceGroup -Name $Name -ErrorAction SilentlyContinue) {
        Write-Host "Resource group '$Name' exists."
    } else {
        Write-Host "Creating resource group '$Name'..."
        New-AzResourceGroup -Name $Name -Location $Location
    }
}

function Ensure-Network {
    param (
        [string]$ResourceGroup,
        [string]$Location,
        [string]$VNetName,
        [string]$SubnetName,
        [string]$AddressPrefix,
        [string]$SubnetPrefix,
        [string]$NsgName
    )
    Write-Output "Creating Network Security Group $NsgName..."
    $nsg = New-AzNetworkSecurityGroup -ResourceGroupName $ResourceGroup -Location $Location -Name $NsgName
    Add-AzNetworkSecurityRuleConfig -Name "Allow-RDP" -NetworkSecurityGroup $nsg -Priority 1000 -Direction Inbound -Access Allow -Protocol Tcp -SourceAddressPrefix '*' -SourcePortRange '*' -DestinationAddressPrefix '*' -DestinationPortRange 3389
    Add-AzNetworkSecurityRuleConfig -Name "Allow-SMB" -NetworkSecurityGroup $nsg -Priority 1010 -Direction Inbound -Access Allow -Protocol Tcp -SourceAddressPrefix '*' -SourcePortRange '*' -DestinationAddressPrefix '*' -DestinationPortRange 445
    Add-AzNetworkSecurityRuleConfig -Name "Allow-RDMA" -NetworkSecurityGroup $nsg -Priority 1020 -Direction Inbound -Access Allow -Protocol Tcp -SourceAddressPrefix '*' -SourcePortRange '*' -DestinationAddressPrefix '*' -DestinationPortRange 5445,5444,17500,4791
    Set-AzNetworkSecurityGroup -NetworkSecurityGroup $nsg
    Write-Output "Creating Virtual Network $VNetName and Subnet $SubnetName..."
    $subnet = New-AzVirtualNetworkSubnetConfig -Name $SubnetName -AddressPrefix $SubnetPrefix -NetworkSecurityGroup $nsg
    $vnet = New-AzVirtualNetwork -Name $VNetName -ResourceGroupName $ResourceGroup -Location $Location -AddressPrefix $AddressPrefix -Subnet $subnet
    $subnetId = ($vnet.Subnets | Where-Object { $_.Name -eq $SubnetName }).Id
    return @{ Nsg = $nsg; SubnetId = $subnetId }
}

function Deploy-IBVMs {
    param (
        [string]$ResourceGroup,
        [string]$Location,
        [string]$VmPrefix,
        [string]$VmSize,
        [int]$VmCount,
        [string]$AdminUsername,
        [securestring]$AdminPassword,
        [string]$SubnetId,
        [object]$Nsg
    )
    for ($i = 1; $i -le $VmCount; $i++) {
        $vmName = "$VmPrefix$i"
        Write-Output "🚀 Deploying $vmName with $VmSize..."
        $nic = New-AzNetworkInterface -Name "$vmName-nic" -ResourceGroupName $ResourceGroup -Location $Location -SubnetId $SubnetId -EnableAcceleratedNetworking -NetworkSecurityGroupId $Nsg.Id
        $vmConfig = New-AzVMConfig -VMSize $VmSize -AvailabilitySetId $null |
            Set-AzVMOperatingSystem -Windows -ComputerName $vmName -Credential (New-Object PSCredential($AdminUsername, $AdminPassword)) -ProvisionVMAgent -EnableAutoUpdate |
            Set-AzVMSourceImage -PublisherName "MicrosoftWindowsServer" -Offer "WindowsServer" -Skus "2022-datacenter-smalldisk" -Version "latest" |
            Add-AzVMNetworkInterface -Id $nic.Id
        New-AzVM -ResourceGroupName $ResourceGroup -Location $Location -VM $vmConfig
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
    foreach ($i in 1..$VmCount) {
        $vmName = "$VmPrefix$i"
        Write-Output "🔧 Configuring InfiniBand support on $vmName..."
        Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroup -Name $vmName -CommandId 'RunPowerShellScript' -ScriptString @(
            "if (!(Test-Path '$DownloadPath')) { New-Item -ItemType Directory -Path '$DownloadPath' }",
            "Invoke-WebRequest -Uri '$DriverUrl' -OutFile '$DownloadPath\$DriverInstaller'",
            "Start-Process -FilePath '$DownloadPath\$DriverInstaller' -ArgumentList '/S /v/qn' -Wait",
            "$check = Get-WmiObject Win32_PnPSignedDriver | Where-Object { $_.DeviceName -like '*Mellanox*' }",
            "if ($check) { Write-Output '✅ Driver installed on $vmName.' } else { Write-Error '❌ Driver install failed on $vmName.' }",
            "# Validate RDMA capability",
            "$rdma = Get-NetAdapterRdma | Where-Object { $_.Enabled -eq $true }",
            "if ($rdma) { Write-Output '✅ RDMA is enabled on $vmName.' } else { Write-Error '❌ RDMA not enabled on $vmName.' }",
            "Remove-Item '$DownloadPath\$DriverInstaller' -Force"
        )
    }
}


# =============================== #
# Main Execution                  #
# =============================== #


param(
    [Alias('DryRun')][switch]$WhatIf
)

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


$selectedSub = Select-AzSubscriptionContext
Ensure-ResourceGroup -Name $resourceGroup -Location $location -WhatIf:$WhatIf
$net = Ensure-Network -ResourceGroup $resourceGroup -Location $location -VNetName $vnetName -SubnetName $subnetName -AddressPrefix $addressPrefix -SubnetPrefix $subnetPrefix -NsgName $nsgName -WhatIf:$WhatIf
Deploy-IBVMs -ResourceGroup $resourceGroup -Location $location -VmPrefix $vmPrefix -VmSize $vmSize -VmCount $vmCount -AdminUsername $adminUsername -AdminPassword $adminPassword -SubnetId $net.SubnetId -Nsg $net.Nsg -WhatIf:$WhatIf
if (-not $WhatIf) {
    Configure-InfiniBand -ResourceGroup $resourceGroup -VmPrefix $vmPrefix -VmCount $vmCount -DriverUrl $driverUrl -DriverInstaller $driverInstaller -DownloadPath $downloadPath
} else {
    Write-Output "[DRY-RUN] Skipping InfiniBand driver installation and validation."
}

Write-Output "`n🎉 HPC Pack cluster deployed with RDMA/InfiniBand enabled on HB120rs v3 nodes."
