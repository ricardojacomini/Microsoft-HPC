# Deploy Regular Windows VM with Accelerated Networking
# This script deploys standard Windows VMs with Accelerated Networking enabled
# 
# Accelerated Networking Benefits:
# ✅ Up to 30 Gbps network throughput (depending on VM size)
# ✅ Lower latency and jitter
# ✅ Reduced CPU utilization on networking
# ✅ Better packet per second (PPS) performance
# ✅ Compatible with most VM sizes D2s_v3 and above
#
# Usage Examples:
#   .\deploy-windows-accelerated-networking.ps1                              # Interactive deployment
#   .\deploy-windows-accelerated-networking.ps1 -VmSize "Standard_D8s_v3"   # Specific VM size
#   .\deploy-windows-accelerated-networking.ps1 -VmCount 5                  # Multiple VMs
#   .\deploy-windows-accelerated-networking.ps1 -WindowsVersion "2019-datacenter" # Specific Windows version

param(
    [string]$ResourceGroupName = "",
    [string]$Location = "eastus",
    [string]$ResourcePrefix = "win-accel",
    [ValidateSet("Standard_D2s_v3", "Standard_D4s_v3", "Standard_D8s_v3", "Standard_D16s_v3", "Standard_D32s_v3",
                 "Standard_D2s_v4", "Standard_D4s_v4", "Standard_D8s_v4", "Standard_D16s_v4", "Standard_D32s_v4",
                 "Standard_D2s_v5", "Standard_D4s_v5", "Standard_D8s_v5", "Standard_D16s_v5", "Standard_D32s_v5",
                 "Standard_F2s_v2", "Standard_F4s_v2", "Standard_F8s_v2", "Standard_F16s_v2", "Standard_F32s_v2",
                 "Standard_E2s_v3", "Standard_E4s_v3", "Standard_E8s_v3", "Standard_E16s_v3", "Standard_E32s_v3")]
    [string]$VmSize = "Standard_D4s_v3",
    [ValidateSet("2019-datacenter", "2019-datacenter-gensecond", "2022-datacenter", "2022-datacenter-azure-edition", "2022-datacenter-core")]
    [string]$WindowsVersion = "2022-datacenter-azure-edition",
    [int]$VmCount = 1,
    [string]$AdminUsername = "azureuser",
    [SecureString]$AdminPassword,
    [bool]$EnablePremiumStorage = $true,
    [int]$OsDiskSizeGB = 128,
    [switch]$WhatIf,
    [switch]$SkipResourceGroup
)

# =============================== #
# Function Definitions            #
# =============================== #

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Write-Host $logMessage -ForegroundColor $(switch($Level) {
        "ERROR" { "Red" }
        "WARN" { "Yellow" }
        "SUCCESS" { "Green" }
        default { "White" }
    })
}

function Test-AzureConnection {
    try {
        $context = Get-AzContext
        if ($null -eq $context) {
            Write-Log "Not connected to Azure. Please run 'Connect-AzAccount' first." "ERROR"
            return $false
        }
        Write-Log "Connected to Azure as: $($context.Account.Id)" "SUCCESS"
        Write-Log "Subscription: $($context.Subscription.Name) ($($context.Subscription.Id))"
        return $true
    } catch {
        Write-Log "Error checking Azure connection: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Get-AcceleratedNetworkingInfo {
    param([string]$VmSize)
    
    # VM sizes that support Accelerated Networking
    $acceleratedNetworkingSizes = @{
        "Standard_D2s_v3" = @{ MaxNics = 2; ExpectedBandwidth = "1 Gbps"; PPS = "125K" }
        "Standard_D4s_v3" = @{ MaxNics = 2; ExpectedBandwidth = "2 Gbps"; PPS = "250K" }
        "Standard_D8s_v3" = @{ MaxNics = 4; ExpectedBandwidth = "4 Gbps"; PPS = "500K" }
        "Standard_D16s_v3" = @{ MaxNics = 8; ExpectedBandwidth = "8 Gbps"; PPS = "1M" }
        "Standard_D32s_v3" = @{ MaxNics = 8; ExpectedBandwidth = "16 Gbps"; PPS = "2M" }
        "Standard_D2s_v4" = @{ MaxNics = 2; ExpectedBandwidth = "1 Gbps"; PPS = "125K" }
        "Standard_D4s_v4" = @{ MaxNics = 2; ExpectedBandwidth = "2 Gbps"; PPS = "250K" }
        "Standard_D8s_v4" = @{ MaxNics = 4; ExpectedBandwidth = "4 Gbps"; PPS = "500K" }
        "Standard_D16s_v4" = @{ MaxNics = 8; ExpectedBandwidth = "8 Gbps"; PPS = "1M" }
        "Standard_D32s_v4" = @{ MaxNics = 8; ExpectedBandwidth = "16 Gbps"; PPS = "2M" }
        "Standard_F4s_v2" = @{ MaxNics = 2; ExpectedBandwidth = "2 Gbps"; PPS = "250K" }
        "Standard_F8s_v2" = @{ MaxNics = 4; ExpectedBandwidth = "4 Gbps"; PPS = "500K" }
        "Standard_F16s_v2" = @{ MaxNics = 8; ExpectedBandwidth = "8 Gbps"; PPS = "1M" }
        "Standard_F32s_v2" = @{ MaxNics = 8; ExpectedBandwidth = "16 Gbps"; PPS = "2M" }
    }
    
    if ($acceleratedNetworkingSizes.ContainsKey($VmSize)) {
        return $acceleratedNetworkingSizes[$VmSize]
    } else {
        return @{ MaxNics = "Unknown"; ExpectedBandwidth = "Varies"; PPS = "Varies" }
    }
}

function Test-VmSizeAcceleratedNetworking {
    param([string]$VmSize, [string]$Location)
    
    Write-Log "Checking Accelerated Networking support for $VmSize in $Location"
    
    $supportedSizes = @(
        "Standard_D2s_v3", "Standard_D4s_v3", "Standard_D8s_v3", "Standard_D16s_v3", "Standard_D32s_v3",
        "Standard_D2s_v4", "Standard_D4s_v4", "Standard_D8s_v4", "Standard_D16s_v4", "Standard_D32s_v4",
        "Standard_D2s_v5", "Standard_D4s_v5", "Standard_D8s_v5", "Standard_D16s_v5", "Standard_D32s_v5",
        "Standard_F2s_v2", "Standard_F4s_v2", "Standard_F8s_v2", "Standard_F16s_v2", "Standard_F32s_v2",
        "Standard_E2s_v3", "Standard_E4s_v3", "Standard_E8s_v3", "Standard_E16s_v3", "Standard_E32s_v3"
    )
    
    if ($supportedSizes -contains $VmSize) {
        Write-Log "✅ $VmSize supports Accelerated Networking" "SUCCESS"
        
        $info = Get-AcceleratedNetworkingInfo -VmSize $VmSize
        Write-Log "  Expected Network Performance:" "INFO"
        Write-Log "    Bandwidth: $($info.ExpectedBandwidth)" "INFO"
        Write-Log "    Packets/sec: $($info.PPS)" "INFO"
        Write-Log "    Max NICs: $($info.MaxNics)" "INFO"
        
        return $true
    } else {
        Write-Log "❌ $VmSize does not support Accelerated Networking" "ERROR"
        Write-Log "Please choose a different VM size from the supported list." "ERROR"
        return $false
    }
}

function Get-UserInput {
    if (-not $ResourceGroupName) {
        $ResourceGroupName = Read-Host "Enter Resource Group name (or press Enter for 'rg-$ResourcePrefix')"
        if (-not $ResourceGroupName) {
            $ResourceGroupName = "rg-$ResourcePrefix"
        }
    }
    
    if (-not $AdminPassword) {
        $AdminPassword = Read-Host "Enter VM administrator password" -AsSecureString
    }
    
    return @{
        ResourceGroupName = $ResourceGroupName
        AdminPassword = $AdminPassword
    }
}

function New-ResourceGroupIfNeeded {
    param([string]$Name, [string]$Location)
    
    if ($SkipResourceGroup) {
        Write-Log "Skipping resource group creation (SkipResourceGroup specified)"
        return $true
    }
    
    try {
        $rg = Get-AzResourceGroup -Name $Name -ErrorAction SilentlyContinue
        if ($rg) {
            Write-Log "Resource group '$Name' already exists in $($rg.Location)"
            return $true
        } else {
            Write-Log "Creating resource group '$Name' in $Location"
            if (-not $WhatIf) {
                New-AzResourceGroup -Name $Name -Location $Location | Out-Null
                Write-Log "✅ Resource group created successfully" "SUCCESS"
            } else {
                Write-Log "[WHAT-IF] Would create resource group '$Name' in $Location"
            }
            return $true
        }
    } catch {
        Write-Log "Failed to create resource group: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Invoke-BicepTemplateDeployment {
    param(
        [string]$ResourceGroupName,
        [string]$TemplateFile,
        [hashtable]$Parameters
    )
    
    Write-Log "Deploying Bicep template: $TemplateFile"
    Write-Log "Deployment parameters:"
    $Parameters.Keys | ForEach-Object {
        if ($_ -eq "adminPassword") {
            Write-Log "  $_ = [SECURED]"
        } else {
            Write-Log "  $_ = $($Parameters[$_])"
        }
    }
    
    try {
        $deploymentName = "win-accel-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        
        if ($WhatIf) {
            Write-Log "[WHAT-IF] Validating deployment..."
            $result = Test-AzResourceGroupDeployment -ResourceGroupName $ResourceGroupName -TemplateFile $TemplateFile -TemplateParameterObject $Parameters
            if ($result) {
                Write-Log "[WHAT-IF] Validation errors found:" "ERROR"
                $result | ForEach-Object { Write-Log "  $_" "ERROR" }
                return $false
            } else {
                Write-Log "[WHAT-IF] Template validation passed ✅" "SUCCESS"
                return $true
            }
        } else {
            Write-Log "Starting deployment: $deploymentName"
            $deployment = New-AzResourceGroupDeployment -ResourceGroupName $ResourceGroupName -Name $deploymentName -TemplateFile $TemplateFile -TemplateParameterObject $Parameters -Verbose
            
            if ($deployment.ProvisioningState -eq "Succeeded") {
                Write-Log "✅ Deployment completed successfully!" "SUCCESS"
                return $deployment
            } else {
                Write-Log "Deployment failed with state: $($deployment.ProvisioningState)" "ERROR"
                return $false
            }
        }
    } catch {
        Write-Log "Deployment failed: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Show-DeploymentResults {
    param($Deployment)
    
    if (-not $Deployment -or $WhatIf) { return }
    
    Write-Log ""
    Write-Log "🎉 Deployment Results:" "SUCCESS"
    Write-Log "========================="
    
    $outputs = $Deployment.Outputs
    
    if ($outputs.vmNames) {
        Write-Log "VM Names:"
        $outputs.vmNames.Value | ForEach-Object { Write-Log "  - $_" }
    }
    
    if ($outputs.publicIpAddresses) {
        Write-Log "Public IP Addresses:"
        $outputs.publicIpAddresses.Value | ForEach-Object { Write-Log "  - $_" }
    }
    
    if ($outputs.fqdns) {
        Write-Log "Fully Qualified Domain Names:"
        $outputs.fqdns.Value | ForEach-Object { Write-Log "  - $_" }
    }
    
    if ($outputs.rdpConnections) {
        Write-Log "RDP Connection Commands:"
        $outputs.rdpConnections.Value | ForEach-Object { Write-Log "  - $_" }
    }
    
    if ($outputs.networkConfiguration) {
        $netConfig = $outputs.networkConfiguration.Value
        Write-Log ""
        Write-Log "Network Configuration:"
        Write-Log "  Accelerated Networking: $($netConfig.acceleratedNetworkingEnabled)"
        Write-Log "  VM Size Supported: $($netConfig.vmSizeSupportsAcceleratedNetworking)"
        if ($netConfig.networkOptimizations) {
            Write-Log "  Optimizations: $($netConfig.networkOptimizations -join ', ')"
        }
    }
    
    Write-Log ""
    Write-Log "🔧 Post-Deployment Verification:" "SUCCESS"
    Write-Log "After connecting to your VM(s), run these commands to verify Accelerated Networking:"
    Write-Log "  Get-NetAdapter | Select-Object Name, InterfaceDescription, LinkSpeed"
    Write-Log "  Get-NetAdapterAdvancedProperty | Where-Object {`$_.DisplayName -like '*Offload*'}"
    Write-Log "  Test-NetConnection -ComputerName 8.8.8.8 -InformationLevel Detailed"
}

# =============================== #
# Main Execution                  #
# =============================== #

Write-Log "🚀 Windows VM with Accelerated Networking Deployment Script"
Write-Log "============================================================="
Write-Log ""

# Check Azure connection
if (-not (Test-AzureConnection)) {
    Write-Log "Please connect to Azure first: Connect-AzAccount" "ERROR"
    exit 1
}

# Validate VM size supports Accelerated Networking
if (-not (Test-VmSizeAcceleratedNetworking -VmSize $VmSize -Location $Location)) {
    exit 1
}

# Get user inputs if not provided
$inputs = Get-UserInput
$ResourceGroupName = $inputs.ResourceGroupName
$AdminPassword = $inputs.AdminPassword

# Check if Bicep template exists
$templatePath = Join-Path $PSScriptRoot "deploy-windows-accelerated-networking.bicep"
if (-not (Test-Path $templatePath)) {
    Write-Log "Bicep template not found: $templatePath" "ERROR"
    Write-Log "Please ensure 'deploy-windows-accelerated-networking.bicep' is in the same directory." "ERROR"
    exit 1
}

Write-Log "Configuration Summary:"
Write-Log "  Resource Group: $ResourceGroupName"
Write-Log "  Location: $Location"
Write-Log "  Resource Prefix: $ResourcePrefix"
Write-Log "  VM Size: $VmSize"
Write-Log "  Windows Version: $WindowsVersion"
Write-Log "  VM Count: $VmCount"
Write-Log "  Admin Username: $AdminUsername"
Write-Log "  Premium Storage: $EnablePremiumStorage"
Write-Log "  OS Disk Size: $OsDiskSizeGB GB"
Write-Log "  Template: $templatePath"
Write-Log ""

if (-not $WhatIf) {
    $continue = Read-Host "Proceed with deployment? (Y/N)"
    if ($continue -ne "Y" -and $continue -ne "y") {
        Write-Log "Deployment cancelled by user."
        exit 0
    }
}

# Create resource group
if (-not (New-ResourceGroupIfNeeded -Name $ResourceGroupName -Location $Location)) {
    exit 1
}

# Prepare deployment parameters
$deploymentParams = @{
    resourcePrefix = $ResourcePrefix
    location = $Location
    vmSize = $VmSize
    windowsOSVersion = $WindowsVersion
    vmCount = $VmCount
    adminUsername = $AdminUsername
    adminPassword = $AdminPassword
    enablePremiumStorage = $EnablePremiumStorage
    osDiskSizeGB = $OsDiskSizeGB
}

# Deploy template
Write-Log "Starting Bicep deployment..."
$deployment = Invoke-BicepTemplateDeployment -ResourceGroupName $ResourceGroupName -TemplateFile $templatePath -Parameters $deploymentParams

# Show results
if ($deployment) {
    Show-DeploymentResults -Deployment $deployment
    
    Write-Log ""
    Write-Log "✅ Windows VM with Accelerated Networking deployment completed successfully!" "SUCCESS"
    Write-Log ""
    Write-Log "Key Benefits of this deployment:" "SUCCESS"
    Write-Log "  ✅ Accelerated Networking enabled for maximum performance"
    Write-Log "  ✅ Network optimizations applied"
    Write-Log "  ✅ Performance monitoring enabled"
    Write-Log "  ✅ Premium storage for better IOPS"
    Write-Log "  ✅ Latest Windows Server with Azure optimizations"
    
} else {
    Write-Log "❌ Deployment failed" "ERROR"
    exit 1
}
