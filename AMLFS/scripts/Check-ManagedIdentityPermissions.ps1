#!/usr/bin/env powershell
<#
.SYNOPSIS
    Check Managed Identity permissions and validate AMLFS deployment readiness

.DESCRIPTION
    This script validates:
    - Managed Identity existence and properties
    - Role assignments for the managed identity
    - Storage account permissions
    - AMLFS resource status
    - Network configuration

.PARAMETER ResourceGroupName
    The name of the resource group containing the managed identity

.PARAMETER ManagedIdentityName
    The name of the managed identity to check (optional - will search if not provided)

.EXAMPLE
    .\Check-ManagedIdentityPermissions.ps1 -ResourceGroupName "aml-rsj-managed-identity-20250721-1521"
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$false)]
    [string]$ManagedIdentityName,
    
    [Parameter(Mandatory=$false)]
    [switch]$ShowAllSubscriptions
)

# Function to write colored output
function Write-ColorOutput {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ForegroundColor,
        [Parameter(Mandatory=$true)]
        [string]$Message
    )
    
    $fc = $host.UI.RawUI.ForegroundColor
    $host.UI.RawUI.ForegroundColor = $ForegroundColor
    Write-Output $Message
    $host.UI.RawUI.ForegroundColor = $fc
}

Write-ColorOutput -ForegroundColor Green -Message "=== Azure Managed Identity Permission Checker ==="
Write-Output ""

# Check if user is logged in
try {
    $currentUser = az account show --query "user.name" -o tsv 2>$null
    if (-not $currentUser) {
        Write-ColorOutput -ForegroundColor Red -Message "Not logged into Azure. Please run 'az login' first."
        exit 1
    }
    Write-ColorOutput -ForegroundColor Green -Message "Logged in as: $currentUser"
} catch {
    Write-ColorOutput -ForegroundColor Red -Message "Error checking Azure login status. Please run 'az login' first."
    exit 1
}

# Get current subscription
$currentSub = az account show --query "{name:name, id:id}" -o json | ConvertFrom-Json
Write-ColorOutput -ForegroundColor Cyan -Message "Current subscription: $($currentSub.name) ($($currentSub.id))"
Write-Output ""

# If no resource group specified, search for resources
if (-not $ResourceGroupName) {
    Write-ColorOutput -ForegroundColor Yellow -Message "Searching for AMLFS-related resources..."
    
    # Search for resource groups with aml-rsj pattern
    $resourceGroups = az group list --query "[?contains(name, 'aml-rsj')].name" -o tsv
    
    if ($resourceGroups) {
        Write-ColorOutput -ForegroundColor Green -Message "Found resource groups:"
        $resourceGroups | ForEach-Object { Write-Output "  - $_" }
        
        if ($resourceGroups.Count -eq 1) {
            $ResourceGroupName = $resourceGroups[0]
            Write-ColorOutput -ForegroundColor Yellow -Message "Using resource group: $ResourceGroupName"
        } else {
            Write-ColorOutput -ForegroundColor Red -Message "Multiple resource groups found. Please specify -ResourceGroupName parameter."
            exit 1
        }
    } else {
        Write-ColorOutput -ForegroundColor Red -Message "No resource groups found matching 'aml-rsj' pattern."
        Write-ColorOutput -ForegroundColor Yellow -Message "Available resource groups:"
        az group list --query "[].name" -o table
        exit 1
    }
}

Write-Output ""
Write-ColorOutput -ForegroundColor Cyan -Message "Checking Resource Group: $ResourceGroupName"

# Check if resource group exists
$rgExists = az group exists --name $ResourceGroupName
if ($rgExists -eq "false") {
    Write-ColorOutput -ForegroundColor Red -Message "Resource group '$ResourceGroupName' does not exist."
    exit 1
}

# Get all resources in the resource group
Write-ColorOutput -ForegroundColor Yellow -Message "Resources in ${ResourceGroupName}:"
$resources = az resource list --resource-group $ResourceGroupName --query "[].{Name:name, Type:type, Location:location}" -o json | ConvertFrom-Json

if (-not $resources) {
    Write-ColorOutput -ForegroundColor Red -Message "No resources found in resource group '$ResourceGroupName'"
    exit 1
}

$resources | ForEach-Object {
    $icon = switch ($_.Type) {
        "Microsoft.ManagedIdentity/userAssignedIdentities" { "ID" }
        "Microsoft.Storage/storageAccounts" { "STORAGE" }
        "Microsoft.StorageCache/amlFileSystems" { "AMLFS" }
        "Microsoft.Network/virtualNetworks" { "VNET" }
        "Microsoft.Network/networkSecurityGroups" { "NSG" }
        default { "RESOURCE" }
    }
    Write-Output "  [$icon] $($_.Name) ($($_.Type))"
}

# Find managed identities
$managedIdentities = $resources | Where-Object { $_.Type -eq "Microsoft.ManagedIdentity/userAssignedIdentities" }

if (-not $managedIdentities) {
    Write-ColorOutput -ForegroundColor Red -Message "No managed identities found in resource group '$ResourceGroupName'"
    exit 1
}

# Select managed identity to check
if ($managedIdentities.Count -eq 1) {
    $ManagedIdentityName = $managedIdentities[0].Name
    Write-ColorOutput -ForegroundColor Yellow -Message "Using managed identity: $ManagedIdentityName"
} elseif ($ManagedIdentityName) {
    $selectedMI = $managedIdentities | Where-Object { $_.Name -eq $ManagedIdentityName }
    if (-not $selectedMI) {
        Write-ColorOutput -ForegroundColor Red -Message "Managed identity '$ManagedIdentityName' not found in resource group."
        Write-ColorOutput -ForegroundColor Yellow -Message "Available managed identities:"
        $managedIdentities | ForEach-Object { Write-Output "  - $($_.Name)" }
        exit 1
    }
} else {
    Write-ColorOutput -ForegroundColor Red -Message "Multiple managed identities found. Please specify -ManagedIdentityName parameter."
    Write-ColorOutput -ForegroundColor Yellow -Message "Available managed identities:"
    $managedIdentities | ForEach-Object { Write-Output "  - $($_.Name)" }
    exit 1
}

Write-Output ""
Write-ColorOutput -ForegroundColor Cyan -Message "Checking Managed Identity: $ManagedIdentityName"

# Get managed identity details
$miDetails = az identity show --name $ManagedIdentityName --resource-group $ResourceGroupName -o json | ConvertFrom-Json

Write-Output "  Principal ID: $($miDetails.principalId)"
Write-Output "  Client ID: $($miDetails.clientId)"
Write-Output "  Location: $($miDetails.location)"

# Check role assignments for the managed identity
Write-ColorOutput -ForegroundColor Yellow -Message "Checking role assignments..."

$roleAssignments = az role assignment list --assignee $miDetails.principalId --query "[].{roleDefinitionName:roleDefinitionName, scope:scope}" -o json | ConvertFrom-Json

if ($roleAssignments) {
    Write-ColorOutput -ForegroundColor Green -Message "Role assignments found:"
    $roleAssignments | ForEach-Object {
        Write-Output "  Role: $($_.roleDefinitionName)"
        Write-Output "  Scope: $($_.scope)"
    }
} else {
    Write-ColorOutput -ForegroundColor Red -Message "No role assignments found for this managed identity."
}

# Check storage accounts in the resource group
$storageAccounts = $resources | Where-Object { $_.Type -eq "Microsoft.Storage/storageAccounts" }

if ($storageAccounts) {
    Write-Output ""
    Write-ColorOutput -ForegroundColor Cyan -Message "Checking Storage Account permissions..."
    
    foreach ($sa in $storageAccounts) {
        Write-Output "  Storage Account: $($sa.Name)"
        
        # Check specific role assignments on this storage account
        $saScope = "/subscriptions/$($currentSub.id)/resourceGroups/$ResourceGroupName/providers/Microsoft.Storage/storageAccounts/$($sa.Name)"
        $saRoleAssignments = az role assignment list --scope $saScope --assignee $miDetails.principalId --query "[].{roleDefinitionName:roleDefinitionName}" -o json | ConvertFrom-Json
        
        if ($saRoleAssignments) {
            Write-ColorOutput -ForegroundColor Green -Message "  Storage permissions found:"
            $saRoleAssignments | ForEach-Object {
                Write-Output "    Role: $($_.roleDefinitionName)"
            }
        } else {
            Write-ColorOutput -ForegroundColor Red -Message "  No storage permissions found"
        }
        
        # Check containers
        try {
            $containers = az storage container list --account-name $sa.Name --auth-mode login --query "[].name" -o tsv 2>$null
            if ($containers) {
                Write-Output "  Containers:"
                $containers | ForEach-Object { Write-Output "    - $_" }
            }
        } catch {
            Write-ColorOutput -ForegroundColor Yellow -Message "  Cannot list containers (may need access key or different permissions)"
        }
    }
}

# Check AMLFS resources
$amlfsResources = $resources | Where-Object { $_.Type -eq "Microsoft.StorageCache/amlFileSystems" }

if ($amlfsResources) {
    Write-Output ""
    Write-ColorOutput -ForegroundColor Cyan -Message "Checking AMLFS resources..."
    
    foreach ($amlfs in $amlfsResources) {
        Write-Output "  AMLFS: $($amlfs.Name)"
        
        try {
            $amlfsResourceId = "/subscriptions/$($currentSub.id)/resourceGroups/$ResourceGroupName/providers/Microsoft.StorageCache/amlFileSystems/$($amlfs.Name)"
            $amlfsDetails = az resource show --ids $amlfsResourceId --query "{provisioningState:properties.provisioningState, health:properties.health, clientInfo:properties.clientInfo}" -o json | ConvertFrom-Json
            
            Write-Output "  Status: $($amlfsDetails.provisioningState)"
            Write-Output "  Health: $($amlfsDetails.health)"
            
            if ($amlfsDetails.clientInfo) {
                Write-ColorOutput -ForegroundColor Green -Message "  Client Info available"
                Write-Output "    Mount Command: mount -t lustre $($amlfsDetails.clientInfo.mgsAddress) /mnt/amlfs"
            }
        } catch {
            Write-ColorOutput -ForegroundColor Yellow -Message "  Could not retrieve AMLFS details"
        }
    }
}

# Check virtual networks
$vnets = $resources | Where-Object { $_.Type -eq "Microsoft.Network/virtualNetworks" }

if ($vnets) {
    Write-Output ""
    Write-ColorOutput -ForegroundColor Cyan -Message "Checking Virtual Network configuration..."
    
    foreach ($vnet in $vnets) {
        Write-Output "  VNet: $($vnet.Name)"
        
        try {
            $vnetDetails = az network vnet show --name $vnet.Name --resource-group $ResourceGroupName --query "{addressSpace:addressSpace.addressPrefixes, subnets:subnets[].{name:name, addressPrefix:addressPrefix, delegations:delegations[].name}}" -o json | ConvertFrom-Json
            
            Write-Output "  Address Space: $($vnetDetails.addressSpace -join ', ')"
            Write-Output "  Subnets:"
            $vnetDetails.subnets | ForEach-Object {
                $delegationInfo = if ($_.delegations) { " (Delegated to: $($_.delegations -join ', '))" } else { "" }
                Write-Output "    - $($_.name): $($_.addressPrefix)$delegationInfo"
            }
        } catch {
            Write-ColorOutput -ForegroundColor Yellow -Message "  Could not retrieve VNet details"
        }
    }
}

Write-Output ""
Write-ColorOutput -ForegroundColor Green -Message "=== Summary ==="

# Generate recommendations
$recommendations = @()

if (-not $roleAssignments) {
    $recommendations += "No role assignments found for managed identity"
}

$requiredRoles = @("Storage Blob Data Contributor", "Storage Account Contributor")
$foundRoles = $roleAssignments | ForEach-Object { $_.roleDefinitionName }
$missingRoles = $requiredRoles | Where-Object { $_ -notin $foundRoles }

if ($missingRoles) {
    $recommendations += "Missing recommended roles: $($missingRoles -join ', ')"
}

if ($storageAccounts -and -not ($roleAssignments | Where-Object { $_.roleDefinitionName -in $requiredRoles })) {
    $recommendations += "Managed Identity lacks storage permissions"
}

if ($recommendations) {
    Write-ColorOutput -ForegroundColor Yellow -Message "Recommendations:"
    $recommendations | ForEach-Object { Write-Output "  - $_" }
} else {
    Write-ColorOutput -ForegroundColor Green -Message "All checks passed! Your managed identity appears to be properly configured."
}

Write-Output ""
Write-ColorOutput -ForegroundColor Cyan -Message "To reproduce this setup:"
Write-Output "1. Use the updated 'infra-managed-identity.bicep' file"
Write-Output "2. Deploy with: az deployment group create --resource-group 'new-rg-name' --template-file 'infra-managed-identity.bicep' --parameters 'availabilityZone=2'"
Write-Output "3. The template will create all necessary resources with proper permissions"
