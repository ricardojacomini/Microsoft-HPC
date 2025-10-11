#  🧮 1. Define Variables in Bash
# If you're using Bash (Linux, macOS, or Windows with WSL or Git Bash), run:
# Define your deployment variables
# NOTE: Based on testing, eastus2 is more reliable for HPC Pack deployments


# Log in and set subscription
# WORKING METHOD - Use PowerShell Az Module:
# Install-Module Az -Force -Scope CurrentUser
# Connect-AzAccount
# Set-AzContext -SubscriptionId "4ff8254c-98ae-4bda-b37f-b30d4b289a5b"
# New-AzResourceGroupDeployment -ResourceGroupName "jacomini-hpcpack-hseries-ib-eastus" -TemplateFile "new-1hn-wincn-ad.json" -TemplateParameterFile "azuredeploy.parameters.json"

# ALTERNATIVE - Azure CLI (if PowerShell doesn't work):
# az cache purge; az logout; az login
# az account set --subscription "4ff8254c-98ae-4bda-b37f-b30d4b289a5b"

# az bicep upgrade, if needed

# Create the resource group
# ---- PowerShell ----- 

# 📋 QUOTA REQUEST NEEDED FOR HB-SERIES
# You need to request quota for Standard HBv3 Family vCPUs
# Go to: Azure Portal > Subscriptions > Usage + quotas > Request increase
$region="eastus"  # Changed to East US for better HB-series availability
$resourceGroup="HPC-PACK-Jacomini-eastus"
# $subscriptionId="<your-subscription-id>"
Write-Host "📍 Region: $region"
Write-Host "📦 Resource Group: $resourceGroup"
Write-Host "⚠️  Warning: eastus region has known DSC extension issues with HPC Pack"

Write-Output "Setting up deployment variables..."

az group create --name $resourceGroup --location $region

# Replace <your-subscription-id> with the actual ID or name of your Azure subscription.
# To find your subscription ID:
# az account list --output table

# 🧠 2. Use Variables in Deployment
# Once your variables are set, you can deploy like this:
# Using the ARM JSON template with DSC fixes

# az bicep build --file "new-1hn-wincn-existing-ad.bicep" --outfile "new-1hn-wincn-existing-ad.json"
# az bicep build --file "new-2hn-wincn-ad.bicep" --outfile "new-2hn-wincn-ad.json"


# az vm list-sizes --location eastus --query "[?contains(name, 'Standard_D4s_v6') || contains(name, 'Standard_HB120rs_v3')]" --output table
# az vm list-skus --location eastus --size Standard_DC4ds_v3 --query '[].{name:name, tier:tier, capabilities:capabilities}' -o json
# az vm list-skus --location eastus --query "[?contains(name,'D') && contains(name,'v5')].{name:name, family:family, sizes:capabilities}" -o table
# az vm list-skus --location eastus --query "[?contains(name, 'Standard_D8s_v5') || contains(name, 'Standard_HB120rs_v3')].{name:name, family:family, size:name, zones: locationInfo[0].zones}" -o table

# 🧪 Optional: Validate Before Deploying
# az deployment group validate --resource-group $resourceGroup `
#  --template-file "new-2hn-wincn-ad.json" `
#   --parameters "@azuredeployHAAD.parameters.json" 2>&1 | Select-Object -First 20

az deployment group validate --resource-group $resourceGroup --template-file 'new-2hn-wincn-ad.json' --parameters '@azuredeployHAAD.parameters.json' -o json | ConvertTo-Json -Depth 6

az deployment group create `
  --resource-group $resourceGroup `
  --template-file "new-2hn-wincn-ad.json" `
  --parameters "@azuredeployHAAD.parameters.json"