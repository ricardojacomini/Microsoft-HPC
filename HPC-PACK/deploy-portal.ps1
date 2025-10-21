# Alternative deployment method using Azure Portal
# If Azure CLI continues to have issues, use this approach:

# Load parameter overrides if present
$paramFile = Join-Path -Path $PSScriptRoot -ChildPath '..\hpc-pack-parameters.json'
$paramFile = (Resolve-Path -Path $paramFile -ErrorAction SilentlyContinue).ProviderPath
$params = $null
if ($paramFile -and (Test-Path $paramFile)) {
	try { $params = Get-Content -Path $paramFile -Raw | ConvertFrom-Json } catch { $params = $null }
}

$rgExample = if ($params -and $params.resourceGroupPrefix) { "$($params.resourceGroupPrefix)-$(Get-Date -Format 'MMddHH')" } else { 'jacomini-hpcpack-hseries-ib-eastus' }
$locExample = if ($params -and $params.location) { $params.location } else { 'East US' }

Write-Host "Azure CLI is experiencing 'content already consumed' errors." -ForegroundColor Yellow
Write-Host "Alternative deployment options:" -ForegroundColor Green
Write-Host ""
Write-Host "OPTION 1: Azure Portal Deployment" -ForegroundColor Cyan
Write-Host "1. Go to: https://portal.azure.com" 
Write-Host "2. Search for 'Deploy a custom template'"
Write-Host "3. Click 'Build your own template in the editor'"
Write-Host "4. Upload the file: new-1hn-wincn-ad.json"
Write-Host "5. Click 'Save'"
Write-Host "6. Fill in parameters or upload azuredeploy.parameters.json"
Write-Host "7. Select Resource Group: [your-resource-group-name]"
Write-Host "8. Click 'Review + create' then 'Create'"
Write-Host ""
Write-Host "OPTION 2: PowerShell Azure Module" -ForegroundColor Cyan
Write-Host "Install-Module Az -Force"
Write-Host "Connect-AzAccount"
Write-Host "Set-AzContext -SubscriptionId '4ff8254c-98ae-4bda-b37f-b30d4b289a5b'"
Write-Host "Remove-AzResourceGroup -Name 'jacomini-hpcpack-hseries-ib-eastus' -Force"
Write-Host "New-AzResourceGroup -Name '$rgExample' -Location '$locExample'"
Write-Host "NO AD"
Write-Host "Test-AzResourceGroupDeployment -ResourceGroupName 'jacomini-hpcpack-hseries-ib-eastus' -TemplateFile 'new-1hn-wincn-ad.bicep' -TemplateParameterFile 'azuredeployNoAD.parameters.json'"
Write-Host "New-AzResourceGroupDeployment -ResourceGroupName 'jacomini-hpcpack-hseries-ib-eastus'-TemplateFile 'new-1hn-wincn-ad.bicep' -TemplateParameterFile 'azuredeployNoAD.parameters.json' -Verbose"
Write-Host ""
Write-Host "Existing AD"
Write-Host "Test-AzResourceGroupDeployment -ResourceGroupName 'jacomini-hpcpack-hseries-ib-eastus' -TemplateFile 'new-1hn-wincn-exisiting-ad.bicep' -TemplateParameterFile 'azuredeploy.parametersAD.json'"
Write-Host "New-AzResourceGroupDeployment -ResourceGroupName 'jacomini-hpcpack-hseries-ib-eastus' -TemplateFile 'new-1hn-wincn-exisiting-ad.bicep' -TemplateParameterFile 'azuredeploy.parametersAD.json' -Verbose"
Write-Host ""
Write-Host "# Deploy with existing HA with AD (using Azure CLI)"
Write-Host "New-AzResourceGroup -Name 'HPC-HA-jacomini' -Location 'southcentralus'"
Write-Host "Test-AzResourceGroupDeployment -ResourceGroupName 'HPC-HA-jacomini' -TemplateFile 'new-2hn-wincn-ad.bicep' -TemplateParameterFile 'azuredeployHAAD.parameters.json'"
Write-Host "New-AzResourceGroupDeployment -ResourceGroupName 'HPC-HA-jacomini' -TemplateFile 'new-2hn-wincn-ad.bicep' -TemplateParameterFile '@azuredeployHAAD.parameters.json' --verbose"
Write-Host ""
Write-Host "OPTION 3: Reset and retry Azure CLI" -ForegroundColor Cyan
Write-Host "# Reset Azure CLI and redeploy"
Write-Host "az extension list-available --output table"
Write-Host "az config set core.collect_telemetry=false"
Write-Host "az logout --username all"
Write-Host "az login --tenant 16b3c013-d300-468d-ac64-7eda0820b6d3"
Write-Host "az account set --subscription '4ff8254c-98ae-4bda-b37f-b30d4b289a5b'"
Write-Host "az keyvault purge --name jacomini-hpcpack-hseries"
Write-Host ""
Write-Host "# Check network configuration"
Write-Host "az network vnet list --resource-group 'jacomini-hpcpack-hseries-ib-eastus' --output table"
Write-Host "az network vnet subnet list --resource-group 'jacomini-hpcpack-hseries-ib-eastus' --vnet-name 'headnodevnet' --output table"
Write-Host ""
Write-Host "# Deploy with existing AD (using Azure CLI)"
Write-Host "az deployment group validate --resource-group 'jacomini-hpcpack-hseries-ib-eastus' --template-file 'new-1hn-wincn-existing-ad.bicep' --parameters '@azuredeploy.parameters.json'"
Write-Host "az deployment group create --resource-group 'jacomini-hpcpack-hseries-ib-eastus' --template-file 'new-1hn-wincn-existing-ad.bicep' --parameters '@azuredeploy.parameters.json' --verbose"
Write-Host ""
Write-Host "# Alternative: Deploy without AD (using Azure CLI)"
Write-Host "az deployment group validate --resource-group 'jacomini-hpcpack-hseries-ib-eastus' --template-file 'new-1hn-wincn-ad.bicep' --parameters '@azuredeployNoAD.parameters.json'"
Write-Host "az deployment group create --resource-group 'jacomini-hpcpack-hseries-ib-eastus' --template-file 'new-1hn-wincn-ad.bicep' --parameters '@azuredeployNoAD.parameters.json' --verbose"
Write-Host ""
Write-Host "# Deploy with existing HA with AD (using Azure CLI)"
Write-Host "az deployment group validate --resource-group 'HPC-HA-jacomini' --template-file 'new-2hn-wincn-ad.bicep' --parameters '@azuredeployHAAD.parameters.json'"
Write-Host "az deployment group create --resource-group 'HPC-HA-jacomini' --template-file 'new-2hn-wincn-ad.bicep' --parameters '@azuredeployHAAD.parameters.json' --verbose"
Write-Host ""