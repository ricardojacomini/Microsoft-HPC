# Azure ML File System (AMLFS) Deployment

This repository contains a clean, minimal Bicep template for deploying Azure ML File Systems without complex RBAC configurations.

## Files

- `templates/infra-basic.bicep` - Minimal Bicep template
- `scripts/Test-AMLFSZones.ps1` - Automated zone testing and deployment script

### How JSON Files Work

**Auto-Generated Files (you don't need to create these):**
- `infra.json` - ARM template automatically created by Azure CLI when you run Bicep commands:
  ```powershell
  az bicep build --file "infra.bicep"  # Explicit compilation
  az deployment group create --template-file "infra.bicep"  # Implicit compilation
  ```
- The process: `infra.bicep` → (Azure CLI compiles) → `infra.json` (ARM template for Azure Portal)
- **These files are temporary** and recreated as needed - no need to keep them in your repository

## Prerequisites

1. **Azure CLI** installed and configured
2. **Login to Azure**: `az login`
3. **PowerShell 5.1+** (for Windows deployment script)

## Pre-Deployment Checks

### Check AMLFS Availability and Capacity

Before deploying, run these commands to check capacity and availability:

```powershell
# 1. Check AMLFS quota and current usage in your target region
az rest --method GET --url "https://management.azure.com/subscriptions/$(az account show --query id -o tsv)/providers/Microsoft.StorageCache/locations/eastus/usages?api-version=2023-05-01"

# 2. Check which regions support AMLFS
az provider show --namespace Microsoft.StorageCache --query "resourceTypes[?resourceType=='amlFilesystems'].locations[]" -o table

# 3. Check if StorageCache provider is registered (should show "Registered")
az provider list --query "[?namespace=='Microsoft.StorageCache'].{Namespace:namespace, State:registrationState}" -o table

# 4. Check your current resource group usage
az resource list --resource-group $resource_group --query "length(@)"
```

**Understanding the Output:**
- `currentValue: 0` - You currently have 0 AMLFS instances
- `limit: 4` - You can deploy up to 4 AMLFS instances in East US
- This means **you have capacity available** for deployment

### Automated Zone Testing Strategy

**Pre-Deployment Zone Validation Script:**
```powershell
# Automated Zone Availability Test Function
function Test-AMLFSZoneAvailability {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ResourceGroup,
        
        [Parameter(Mandatory=$false)]
        [string]$TemplateFile = "templates/infra-basic.bicep"
    )
    
    Write-Host "=== AMLFS Zone Availability Testing ===" -ForegroundColor Green
    
    # Test all zones
    $zones = @(1, 2, 3)
    $results = @{}
    
    foreach ($zone in $zones) {
        Write-Host "Testing Zone $zone..." -ForegroundColor Yellow
        
        # Create temporary template with specific zone
        $tempTemplate = "temp-zone$zone.bicep"
        (Get-Content $TemplateFile) -replace "zones: \[.*\]", "zones: [ $zone ]" | Set-Content $tempTemplate
        
        # Validate deployment
        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        try {
            $result = az deployment group validate --resource-group $ResourceGroup --template-file $tempTemplate --parameters fsname="test-z$zone-$timestamp" --query "properties.provisioningState" -o tsv 2>$null
            $results[$zone] = $result
            
            if ($result -eq "Succeeded") {
                Write-Host "✅ Zone $zone: AVAILABLE (validation passed)" -ForegroundColor Green
            } else {
                Write-Host "❌ Zone $zone: FAILED validation" -ForegroundColor Red
            }
        }
        catch {
            Write-Host "❌ Zone $zone: ERROR during validation" -ForegroundColor Red
            $results[$zone] = "Error"
        }
        
        # Cleanup temp file
        Remove-Item $tempTemplate -ErrorAction SilentlyContinue
    }
    
    # Show recommendations
    Write-Host ""
    Write-Host "🎯 RECOMMENDATIONS:" -ForegroundColor Cyan
    $availableZones = $results.Keys | Where-Object { $results[$_] -eq "Succeeded" }
    
    if ($availableZones.Count -gt 0) {
        Write-Host "Available zones for deployment: $($availableZones -join ', ')" -ForegroundColor Green
        Write-Host "Recommended: Try Zone $($availableZones[0]) first" -ForegroundColor Yellow
        
        # Update template with best zone
        $bestZone = $availableZones[0]
        (Get-Content $TemplateFile) -replace "zones: \[.*\]", "zones: [ $bestZone ]" | Set-Content $TemplateFile
        Write-Host "✅ Updated $TemplateFile to use Zone $bestZone" -ForegroundColor Green
    } else {
        Write-Host "⚠️  No zones passed validation - check template or try different region" -ForegroundColor Red
    }
    
    return $results
}

# Usage Example:
# Test-AMLFSZoneAvailability -ResourceGroup "aml-rsj"
```

**Quick Zone Test (One-liner):**
```powershell
# Run this before deployment to auto-configure best available zone
Test-AMLFSZoneAvailability -ResourceGroup "aml-rsj"
```

**Option A: Try zones sequentially**
```bicep
// In your infra.bicep, change the zones array:
zones: [ 1 ]  // Try zone 1 first (most common)
zones: [ 2 ]  // If zone 1 fails due to capacity
zones: [ 3 ]  // If zone 2 fails due to capacity
```

**Option B: Multi-zone deployment (if supported)**
```bicep
zones: [ 1, 2, 3 ]  // Let Azure choose available zone
```

## Quick Start

### Option 1: Fully Automated Deployment (Recommended)

```powershell
# Automated zone testing and deployment - all in one!
```powershell
# All-in-one: test zones and deploy to the best available zone
.\scripts\Test-AMLFSZones.ps1 -ResourceGroup "aml-rsj" -Location "eastus"
```
```

### Option 2: Manual Deployment with Zone Testing

```powershell
# Clear Azure CLI cache and define variables
az cache purge 
$resource_group = "aml-rsj-managed-identity-$(Get-Date -Format 'yyyyMMdd-HHmm')"
$location = "eastus"

# Create the resource group if it doesn't exist
az group create --name $resource_group --location $location

# Step 1: Check AMLFS quota and provider registration
Write-Host "Checking AMLFS quota..." -ForegroundColor Yellow
az rest --method GET --url "https://management.azure.com/subscriptions/$(az account show --query id -o tsv)/providers/Microsoft.StorageCache/locations/$location/usages?api-version=2023-05-01" --query "value[]" -o table

# Check if StorageCache provider is registered
az provider register --namespace Microsoft.StorageCache
az provider show --namespace Microsoft.StorageCache --query "registrationState" -o tsv

# Step 2: Validate template before deployment
Write-Host "Validating Bicep template..." -ForegroundColor Yellow
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
az deployment group validate --resource-group $resource_group --template-file "infra-managed-identity.bicep" --parameters "availabilityZone=2" --name "validate-$timestamp"

# Step 3: Deploy with recommended zone (use What-If first)
Write-Host "Checking deployment plan..." -ForegroundColor Yellow
az deployment group what-if --resource-group $resource_group --template-file "infra-managed-identity.bicep" --parameters "availabilityZone=2" --name "deploy-$timestamp"

# Step 4: Actual deployment
Write-Host "Deploying resources..." -ForegroundColor Green
az deployment group create --resource-group $resource_group --template-file "infra-managed-identity.bicep" --parameters "availabilityZone=2" --name "deploy-$timestamp"
```

### Option 3: Manual Deployment (Original Method)

```powershell
az cache purge 

# Define your variables
$resource_group = "aml-rsj"
$location = "eastus"

# Get your principal ID (Azure AD Object ID)
$principalId = az ad signed-in-user show --query id -o tsv

# Create the resource group
az group create --name $resource_group --location $location

# Recommended validation approach (avoids "content consumed" errors)
az bicep build --file "infra.bicep"

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

# Deploy with unique deployment name
az deployment group create --resource-group $resource_group --template-file "infra.bicep" --parameters principalId=$principalId --name "deploy-$timestamp"
```

#### Alternative ways to get your Principal ID:

**Method 1: Azure CLI (PowerShell)**
```powershell
$principalId = az ad signed-in-user show --query id -o tsv
Write-Host "Your Principal ID: $principalId"
```

**Method 2: Azure CLI (Bash)**
```bash
PRINCIPAL_ID=$(az ad signed-in-user show --query id -o tsv)
echo "Your Principal ID: $PRINCIPAL_ID"
```

**Method 3: Azure PowerShell**
```powershell
$principalId = (Get-AzContext).Account.ExtendedProperties.HomeAccountId.Split('.')[0]
Write-Host "Your Principal ID: $principalId"
```

**Method 4: Azure Portal**
1. Go to Azure Portal → Azure Active Directory → Users
2. Find your user account
3. Copy the "Object ID"

#### How to List Your Resource Groups:

**Method 1: Simple list**
```powershell
az group list --query "[].name" -o table
```

**Method 2: Detailed information**
```powershell
az group list --query "[].{Name:name, Location:location, State:properties.provisioningState}" -o table
```

**Method 3: Filter by location**
```powershell
az group list --query "[?location=='eastus'].name" -o table
```

## What Gets Deployed

```
┌─────────────────┐    ┌─────────────────┐
│   commonNsg     │    │  storageAccount │
│ NetworkSecGroup │    │  StorageAccount │
└─────────┬───────┘    └─────────────────┘
          │
          │
┌─────────▼───────┐
│  virtualNetwork │
│ VirtualNetworks │
└─────────┬───────┘
          │
          │
┌─────────▼───────┐
│   amlfsSubnet   │
│     Subnet      │
└─────────┬───────┘
          │
          │
┌─────────▼───────┐
│   fileSystem    │
│   AMLFS/Cache   │
└─────────────────┘
```

### Resources Deployed:
- **Virtual Network** - Single subnet for AMLFS (10.242.1.0/24)
- **Network Security Group** - Lustre-specific security rules (ports 988, 1019)
- **Storage Account** - Basic storage (no containers in this minimal setup)
- **Azure ML File System** - 8TiB AMLFS with Premium-250 SKU

## Troubleshooting

### Common Issues and Solutions

1. **"Content already consumed" Error**
   ```
   Error: The content for this response was already consumed
   ```
   **Solutions** (try in order):
   
   **Option A: Clear Azure CLI cache**
   ```powershell
   az cache purge
   $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
   az deployment group create --name "deploy-$timestamp" --resource-group $resource_group --template-file "infra.bicep" --parameters principalId=$principalId
   ```
   
   **Option B: Use subscription-level deployment**
   ```powershell
   $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
   az deployment sub create --location $location --template-file "infra.bicep" --parameters principalId=$principalId --name "deploy-$timestamp"
   ```
   
   **Option C: Use ARM template directly**
   ```powershell
   az bicep build --file "infra.bicep" --outfile "temp-deploy.json"
   $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
   az deployment group create --name "deploy-$timestamp" --resource-group $resource_group --template-file "temp-deploy.json" --parameters principalId=$principalId
   Remove-Item "temp-deploy.json"
   ```

2. **BCP081 Warning (Expected and Safe)**
   ```
   Warning BCP081: Resource type "Microsoft.StorageCache/amlFileSystems@2021-11-01-preview" does not have types available.
   ```
   **This is expected** - AMLFS uses a preview API version. The warning doesn't prevent deployment and is safe to ignore.

4. **AMLFS Capacity/Zone Issues**
   ```
   Error: Unable to deploy resource due to a capacity issue in availability zone 'X'
   ```
   **Solutions**:
   
   **Check AMLFS availability before deployment:**
   ```powershell
   # Check if AMLFS is available in your region
   az vm list-skus --location eastus --resource-type "Microsoft.StorageCache/amlFileSystems" --query "[].{Name:name, Locations:locations, Zones:locationInfo[0].zones}" -o table
   ```
   
   **Try different zones in template:**
   ```bicep
   zones: [ 1 ]  // Try zone 1 first
   zones: [ 2 ]  // If zone 1 fails, try zone 2  
   zones: [ 3 ]  // If zone 2 fails, try zone 3
   ```
   
   **Check alternative regions:**
   ```powershell
   # Check AMLFS availability in other regions
   az vm list-skus --resource-type "Microsoft.StorageCache/amlFileSystems" --query "[].{Name:name, Locations:locations, Zones:locationInfo[0].zones}" -o table
   ```
   
   **Alternative: Use smaller capacity first:**
   ```bicep
   storageCapacityTiB: 4  // Try smaller capacity if 8TiB fails
   ```

5. **Login Issues**: Run `az login` and ensure you have proper permissions

4. **Quota Issues**: Check Azure subscription quotas for the target region
   ```powershell
   # Check compute quotas in your region
   az vm list-usage --location eastus --query "[?contains(name.value, 'StorageCache')]"
   
   # Check overall quotas for your subscription
   az vm list-usage --location eastus --query "[?currentValue >= 80*limit/100]" --output table
   ```

5. **Permission Issues**: Ensure you have Contributor role on the subscription/resource group

6. **Template Issues**: Verify `infra.bicep` exists in the current directory

## Clean Up

To remove all resources:
```bash
az group delete --name "your-resource-group" --yes --no-wait
```

## ✅ What's New - Automated Zone Testing

This repository now includes **automated zone testing** to eliminate capacity issues:

### 🎯 Key Features Added:

1. **Zone Parameter in Template**: `templates/infra-basic.bicep` now accepts `availabilityZone` parameter
2. **Automated Testing Script**: `scripts/Test-AMLFSZones.ps1` tests all zones before deployment
3. **Smart Recommendations**: Script automatically selects best available zone
4. **Fallback Support**: If one zone fails, script suggests alternatives

### 🚀 Quick Start (Automated):

```powershell
# Test all zones and deploy with best option
.\scripts\Test-AMLFSZones.ps1 -ResourceGroup "aml-rsj"
```

### 📊 Your Current Status:
- ✅ **AMLFS Quota**: 0/4 used (plenty available)
- ✅ **All Zones Available**: 1, 2, 3 all pass validation  
- ✅ **Recommended**: Zone 1 for deployment
- ✅ **Template Ready**: Zone parameter integrated

### 🛠️ Manual Override:
```powershell
# Deploy with specific zone
az deployment group create --resource-group "aml-rsj" --template-file "templates/infra-basic.bicep" --parameters "availabilityZone=2" --name "deploy-$(Get-Date -Format "yyyyMMdd-HHmmss")"
```
