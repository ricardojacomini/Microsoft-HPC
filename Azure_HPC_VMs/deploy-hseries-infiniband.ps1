# Deploy H-Series VM with InfiniBand Extension
# This script deploys the Bicep template to create H-series VMs with Azure's native InfiniBand extension
# 
# Advantages over manual driver installation:
# ✅ Automatic driver installation via Azure extension
# ✅ No need to download/manage driver executables  
# ✅ Automatic driver updates via autoUpgradeMinorVersion
# ✅ Simplified deployment process
# ✅ Azure-managed driver compatibility
#
# Usage Examples:
#   .\deploy-hseries-infiniband.ps1                                          # Interactive deployment
#   .\deploy-hseries-infiniband.ps1 -ResourceGroupName "rg-hpc" -Location "eastus"  # Quick deployment
#   .\deploy-hseries-infiniband.ps1 -VmCount 3 -VmSize "Standard_HB120rs_v3"        # Scale deployment

param(
    [string]$ResourceGroupName = "",
    [string]$Location = "eastus",
    [string]$ResourcePrefix = "hseries-ib",
    [ValidateSet("Standard_HC44rs", "Standard_HC44-16rs", "Standard_HC44-32rs", 
                 "Standard_HB120rs_v3", "Standard_HB120-16rs_v3", "Standard_HB120-32rs_v3", "Standard_HB120-64rs_v3",
                 "Standard_HB176rs_v4", "Standard_HB60rs", "Standard_ND40rs_v2")]
    [string]$VmSize = "Standard_HC44-16rs",
    [int]$VmCount = 1,
    [string]$AdminUsername = "azureuser",
    [SecureString]$AdminPassword,
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

function Test-VmSizeAvailability {
    param(
        [string]$Location,
        [string]$VmSize
    )
    
    Write-Log "Checking VM size availability: $VmSize in $Location"
    try {
        $skus = Get-AzComputeResourceSku | Where-Object { 
            $_.Locations -contains $Location -and 
            $_.Name -eq $VmSize -and
            $_.ResourceType -eq "virtualMachines"
        }
        
        if ($skus) {
            # Check for restrictions
            $restrictions = $skus.Restrictions | Where-Object { $_.Type -eq "Location" }
            if ($restrictions) {
                Write-Log "VM size $VmSize has restrictions in $Location" "WARN"
                return $false
            }
            Write-Log "✅ VM size $VmSize is available in $Location" "SUCCESS"
            return $true
        } else {
            Write-Log "VM size $VmSize is not available in $Location" "ERROR"
            return $false
        }
    } catch {
        Write-Log "Could not verify VM size availability: $($_.Exception.Message)" "WARN"
        return $true  # Assume available if we can't check
    }
}

function New-ResourceGroupIfNeeded {
    param(
        [string]$Name,
        [string]$Location
    )
    
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

function Deploy-BicepTemplate {
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
        $deploymentName = "hseries-infiniband-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        
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
    
    if ($outputs.deploymentSummary) {
        $summary = $outputs.deploymentSummary.Value
        Write-Log ""
        Write-Log "Deployment Summary:"
        Write-Log "  InfiniBand Enabled: $($summary.infiniBandEnabled)"
        Write-Log "  Accelerated Networking: $($summary.acceleratedNetworking)"
        Write-Log "  Extensions Installed: $($summary.extensions -join ', ')"
    }
    
    Write-Log ""
    Write-Log "🔧 Post-Deployment Verification:" "SUCCESS"
    Write-Log "After connecting to your VM(s), run these commands to verify InfiniBand:"
    Write-Log "  Get-NetAdapterRdma"
    Write-Log "  Get-SmbClientNetworkInterface"
    Write-Log "  Get-NetAdapter | Where-Object { `$_.InterfaceDescription -like '*Mellanox*' }"
}

# =============================== #
# Main Execution                  #
# =============================== #

Write-Log "🚀 H-Series InfiniBand VM Deployment Script"
Write-Log "============================================="
Write-Log ""

# Check Azure connection
if (-not (Test-AzureConnection)) {
    Write-Log "Please connect to Azure first: Connect-AzAccount" "ERROR"
    exit 1
}

# Get user inputs if not provided
$inputs = Get-UserInput
$ResourceGroupName = $inputs.ResourceGroupName
$AdminPassword = $inputs.AdminPassword

# Validate VM size availability
if (-not (Test-VmSizeAvailability -Location $Location -VmSize $VmSize)) {
    Write-Log "Selected VM size is not available. Please choose a different size or location." "ERROR"
    exit 1
}

# Check if Bicep template exists
$templatePath = Join-Path $PSScriptRoot "deploy-hseries-infiniband.bicep"
if (-not (Test-Path $templatePath)) {
    Write-Log "Bicep template not found: $templatePath" "ERROR"
    Write-Log "Please ensure 'deploy-hseries-infiniband.bicep' is in the same directory." "ERROR"
    exit 1
}

Write-Log "Configuration Summary:"
Write-Log "  Resource Group: $ResourceGroupName"
Write-Log "  Location: $Location"
Write-Log "  Resource Prefix: $ResourcePrefix"
Write-Log "  VM Size: $VmSize"
Write-Log "  VM Count: $VmCount"
Write-Log "  Admin Username: $AdminUsername"
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
    vmCount = $VmCount
    adminUsername = $AdminUsername
    adminPassword = $AdminPassword
}

# Deploy template
Write-Log "Starting Bicep deployment..."
$deployment = Deploy-BicepTemplate -ResourceGroupName $ResourceGroupName -TemplateFile $templatePath -Parameters $deploymentParams

# Show results
if ($deployment) {
    Show-DeploymentResults -Deployment $deployment
    
    Write-Log ""
    Write-Log "✅ H-Series InfiniBand deployment completed successfully!" "SUCCESS"
    Write-Log ""
    Write-Log "Key Benefits of this deployment:" "SUCCESS"
    Write-Log "  ✅ Azure-managed InfiniBand driver installation"
    Write-Log "  ✅ Automatic driver updates enabled"
    Write-Log "  ✅ Accelerated networking configured"
    Write-Log "  ✅ RDMA optimization applied"
    Write-Log "  ✅ No manual driver management required"
    
} else {
    Write-Log "❌ Deployment failed" "ERROR"
    exit 1
}
