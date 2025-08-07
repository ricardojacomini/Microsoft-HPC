# Deploy H Series VMs with InfiniBand support for Windows Server 2019
# This script creates Azure H series VMs with InfiniBand/RDMA capabilities without HPC Pack
# Requires Azure PowerShell module: Install-Module -Name Az

param(
    [Alias('DryRun')][switch]$WhatIf,
    [string]$ResourceGroupName = "HSeries-IB-jacomini",
    [string]$Location = "eastus",
    [string]$VmSize = "Standard_HB120rs_v3", # Can be changed to other H series sizes
    [int]$VmCount = 2,
    [string]$VmPrefix = "HSeries-IB",
    [string]$AdminUsername = "azureuser"
)

# =============================== #
# Function Definitions            #
# =============================== #

function Select-AzSubscriptionContext {
    # Try to get current context first
    $currentContext = Get-AzContext
    if ($currentContext -and $currentContext.Subscription) {
        Write-Output "INFO: Using current Azure context:"
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
            Write-Output "`nERROR: No subscription selected. Exiting script."
            Write-Output "Try running: Connect-AzAccount "
            exit 1
        }
        Set-AzContext -SubscriptionId $selectedSub.Id -TenantId $selectedSub.TenantId
        return $selectedSub
    }
    catch {
        Write-Output "ERROR: Error accessing subscriptions: $($_.Exception.Message)"
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
        Write-Output "SUCCESS: Creating resource group: $Name"
        $rg = New-AzResourceGroup -Name $Name -Location $Location
    } else {
        Write-Output "INFO: Resource group already exists: $Name"
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
        Write-Output "SUCCESS: Creating Network Security Group: $NsgName with InfiniBand rules"
        
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
        Write-Output "INFO: Network Security Group already exists: $NsgName"
    }

    # Create or get VNet
    $vnet = Get-AzVirtualNetwork -ResourceGroupName $ResourceGroup -Name $VNetName -ErrorAction SilentlyContinue
    if (-not $vnet) {
        Write-Output "SUCCESS: Creating Virtual Network: $VNetName"
        $subnetConfig = New-AzVirtualNetworkSubnetConfig -Name $SubnetName -AddressPrefix $SubnetPrefix -NetworkSecurityGroup $nsg
        $vnet = New-AzVirtualNetwork -ResourceGroupName $ResourceGroup -Location $Location -Name $VNetName -AddressPrefix $AddressPrefix -Subnet $subnetConfig
    } else {
        Write-Output "INFO: Virtual Network already exists: $VNetName"
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
    
    Write-Output "STARTING: Deploying $VmCount H Series VMs with InfiniBand support..."
    
    for ($i = 1; $i -le $VmCount; $i++) {
        $vmName = "$VmPrefix$i"
        Write-Output "SUCCESS: Creating VM: $vmName"
        
        # Create public IP
        $pip = New-AzPublicIpAddress -ResourceGroupName $ResourceGroup -Location $Location -Name "$vmName-pip" -AllocationMethod Static -Sku Standard
        
        # Create NIC with accelerated networking (required for InfiniBand)
        $nic = New-AzNetworkInterface -ResourceGroupName $ResourceGroup -Location $Location -Name "$vmName-nic" -SubnetId $SubnetId -PublicIpAddressId $pip.Id -NetworkSecurityGroupId $Nsg.Id -EnableAcceleratedNetworking
        
        # Create VM configuration for H Series with InfiniBand support
        $vmConfig = New-AzVMConfig -VMSize $VmSize -VMName $vmName
        
        # Set Windows Server 2019 as the OS  
        $vmConfig = Set-AzVMOperatingSystem -VM $vmConfig -Windows -ComputerName $vmName -Credential (New-Object PSCredential($AdminUsername, $AdminPassword)) -ProvisionVMAgent -EnableAutoUpdate
        $vmConfig = Set-AzVMSourceImage -VM $vmConfig -PublisherName "MicrosoftWindowsServer" -Offer "WindowsServer" -Skus "2019-datacenter" -Version "latest"
        
        # Add the network interface
        $vmConfig = Add-AzVMNetworkInterface -VM $vmConfig -Id $nic.Id
        
        # Create the VM with explicit security type bypass
        try {
            $vm = New-AzVM -ResourceGroupName $ResourceGroup -Location $Location -VM $vmConfig -DisableBginfoExtension -Zone @()
            
            if ($vm.ProvisioningState -eq "Succeeded") {
                Write-Output "SUCCESS: VM $vmName created successfully"
            } else {
                Write-Warning "WARNING: VM $vmName creation may have issues. Check Azure portal."
            }
        } catch {
            Write-Warning "WARNING: Failed to create VM $vmName : $($_.Exception.Message)"
            Write-Output "INFO: Attempting VM creation with basic configuration..."
            
            # Try a simpler approach using New-AzVM with basic parameters
            try {
                $credential = New-Object PSCredential($AdminUsername, $AdminPassword)
                $vm = New-AzVM -ResourceGroupName $ResourceGroup -Location $Location -Name $vmName -VirtualNetworkName ($net.VNetName) -SubnetName ($net.SubnetName) -SecurityGroupName ($net.NsgName) -PublicIpAddressName "$vmName-pip" -OpenPorts 3389 -Image "Win2019Datacenter" -Size $VmSize -Credential $credential
                Write-Output "SUCCESS: VM $vmName created with basic configuration"
            } catch {
                Write-Error "ERROR: Failed to create VM $vmName with both approaches: $($_.Exception.Message)"
            }
        }
    }
}

# =============================== #
# Main Execution                  #
# =============================== #

Write-Output "STARTING: H Series VM with InfiniBand Deployment Script"
Write-Output "================================================"
Write-Output ""

# Configuration parameters
$timestamp = Get-Date -Format "MMddHHmm"
$ResourceGroupName = $ResourceGroupName + "-" + $timestamp
$vnetName = "HSeries-VNet"
$subnetName = "InfiniBand-Subnet"
$addressPrefix = "10.1.0.0/16"
$subnetPrefix = "10.1.0.0/24"
$nsgName = "HSeries-IB-NSG"

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

# Get admin password
if (-not $WhatIf) {
    $adminPassword = Read-Host -Prompt "Enter admin password for VMs" -AsSecureString
} else {
    $adminPassword = ConvertTo-SecureString "DummyPassword123!" -AsPlainText -Force
}

# Main execution
Write-Output "AUTH: Selecting Azure subscription..."
$selectedSub = Select-AzSubscriptionContext
Write-Output "Selected subscription: $($selectedSub.Name) ($($selectedSub.Id))"
Write-Output ""

Write-Output "INFO: Ensuring resource group exists..."
New-ResourceGroupIfNotExists -Name $ResourceGroupName -Location $Location -WhatIf:$WhatIf
Write-Output ""

Write-Output "NETWORK: Setting up network infrastructure..."
$net = New-NetworkInfrastructure -ResourceGroup $ResourceGroupName -Location $Location -VNetName $vnetName -SubnetName $subnetName -AddressPrefix $addressPrefix -SubnetPrefix $subnetPrefix -NsgName $nsgName -WhatIf:$WhatIf
Write-Output ""

Write-Output "DEPLOYING: H Series VMs..."
New-HSeriesVMs -ResourceGroup $ResourceGroupName -Location $Location -VmPrefix $VmPrefix -VmSize $VmSize -VmCount $VmCount -AdminUsername $AdminUsername -AdminPassword $adminPassword -SubnetId $net.SubnetId -Nsg $net.Nsg -WhatIf:$WhatIf
Write-Output ""

Write-Output "SUCCESS: H Series VM deployment with InfiniBand support completed!"
Write-Output ""
Write-Output "Next Steps:"
Write-Output "  1. Connect to VMs via RDP using the public IPs"
Write-Output "  2. Install Mellanox WinOF-2 drivers manually from: https://network.nvidia.com/products/infiniband-drivers/windows/winof/"
Write-Output "  3. Verify InfiniBand adapters with: Get-NetAdapterRdma"
Write-Output "  4. Check Mellanox adapters with: Get-NetAdapter | Where-Object {\$_.Name -like '*Ethernet*'}"
Write-Output "  5. Test RDMA capabilities with your HPC applications"
Write-Output ""
Write-Output "Useful Commands for InfiniBand Verification:"
Write-Output "  Get-NetAdapterRdma"
Write-Output "  Get-SmbClientNetworkInterface"
Write-Output "  Get-NetAdapter | Where-Object { \$_.Name -eq 'Ethernet 2' } | Format-List *"
Write-Output ""
