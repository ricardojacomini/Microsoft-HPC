<#
generate-primaryScriptUri.ps1

Uploads KeyVaultCertificate.ps1 (or any PS1) to a storage account container using your Azure login
and prints a user-delegation SAS URL you can pass as `primaryScriptUri` to the Bicep template.

Usage examples (PowerShell):

# Basic (existing storage account + container)
.
$sa = 'mystorageacctname'
$container = 'scripts'
$localFile = 'C:\path\to\KeyVaultCertificate.ps1'
.
.
# Create container, upload and get primaryScriptUri
.
PS> .\generate-primaryScriptUri.ps1 -StorageAccountName $sa -ContainerName $container -LocalFile $localFile

# Full example including resource group creation and template deploy (you can copy/paste):
# $region = 'eastus'
# $resourceGroup = 'HPC-PACK-Jacomini-23'
# $principalId = az ad signed-in-user show --query id --output tsv
# az group create --name $resourceGroup --location $region
# (run this script to upload and get $primaryScriptUri)
# az deployment group create --resource-group $resourceGroup --template-file "vault-1hn-wincn-ad.json" --parameters "@parametersFile.json" --parameters certOfficerPrincipalId=$principalId primaryScriptUri="$primaryScriptUri"

# Notes
# - This script uses `az storage blob upload --auth-mode login` and `az storage blob generate-sas --auth-mode login`
#   to avoid using storage account keys.
# - You must be logged in with `az login` and have rights to create user-delegation SAS (Storage Blob Data Contributor or equivalent) or be the owner of the account.
# - If the storage account has network restrictions, run this from a machine that can access the storage endpoint or use a storage account that allows access from your client.
#>
param(
    [Parameter(Mandatory=$true)]
    [string]$StorageAccountName,

    [Parameter(Mandatory=$false)]
    [string]$ContainerName = 'scripts',

    [Parameter(Mandatory=$true)]
    [string]$LocalFile,

    [Parameter(Mandatory=$false)]
    [int]$ExpiryDays = 7,

    [Parameter(Mandatory=$false)]
    [string]$ResourceGroup = '',

    [Parameter(Mandatory=$false)]
    [string]$Location = 'eastus',

    [Parameter(Mandatory=$false)]
    [switch]$CreateStorageAccount
)

function ExitWithError([string]$msg, [int]$code=1) {
    Write-Error $msg
    exit $code
}

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    ExitWithError 'az CLI not found in PATH. Install Azure CLI and login with `az login`.'
}

# validate local file
if (-not (Test-Path -Path $LocalFile)) {
    ExitWithError "Local file not found: $LocalFile"
}

# Optional: create resource group
if ($ResourceGroup -ne '') {
    Write-Host "Ensuring resource group $ResourceGroup exists in $Location..."
    az group create --name $ResourceGroup --location $Location | Out-Null
}

# Create storage account if requested
if ($CreateStorageAccount) {
    Write-Host "Creating storage account $StorageAccountName in resource group $ResourceGroup..."
    if ($ResourceGroup -eq '') { ExitWithError 'To create a storage account you must provide -ResourceGroup.' }
    az storage account create --name $StorageAccountName --resource-group $ResourceGroup --location $Location --sku Standard_LRS | Out-Null
}

Write-Host "Creating container '$ContainerName' (if not exists) in account $StorageAccountName..."
az storage container create --account-name $StorageAccountName --name $ContainerName --auth-mode login | Out-Null

# Upload the blob
$blobName = Split-Path -Path $LocalFile -Leaf
Write-Host "Uploading $LocalFile to $StorageAccountName/$ContainerName/$blobName ..."
az storage blob upload --account-name $StorageAccountName --container-name $ContainerName --name $blobName --file "$LocalFile" --auth-mode login | Out-Null

# Generate a user-delegation SAS (auth-mode login). Expiry in UTC
$expiry = (Get-Date).ToUniversalTime().AddDays($ExpiryDays).ToString('yyyy-MM-ddTHH:mmZ')
Write-Host "Generating user-delegation SAS (expires $expiry)..."

try {
    $sas = az storage blob generate-sas --account-name $StorageAccountName --container-name $ContainerName --name $blobName --permissions r --expiry $expiry --auth-mode login --https-only --output tsv
} catch {
    ExitWithError "Failed to generate SAS: $($_.Exception.Message)"
}

$primaryScriptUri = "https://$($StorageAccountName).blob.core.windows.net/$ContainerName/$blobName?$sas"

Write-Host "\nprimaryScriptUri:" -ForegroundColor Green
Write-Host $primaryScriptUri -ForegroundColor Yellow

# Print a recommended deployment command snippet (PowerShell-friendly)
Write-Host "\nRecommended deployment command (PowerShell):" -ForegroundColor Cyan
Write-Host "`$region" -ForegroundColor Gray
Write-Host "`$resourceGroup" -ForegroundColor Gray
Write-Host "`$principalId = az ad signed-in-user show --query id --output tsv" -ForegroundColor Gray
Write-Host "az group create --name `$resourceGroup --location `$region" -ForegroundColor Gray
Write-Host "az deployment group create --resource-group `$resourceGroup --template-file 'vault-1hn-wincn-ad.json' --parameters '@parametersFile.json' --parameters certOfficerPrincipalId=`$principalId primaryScriptUri=\"$primaryScriptUri\"" -ForegroundColor Gray

# Also copy to clipboard on Windows if available
if (Get-Command Set-Clipboard -ErrorAction SilentlyContinue) {
    try { $primaryScriptUri | Set-Clipboard; Write-Host "(primaryScriptUri copied to clipboard)" -ForegroundColor Green } catch {}
}

Write-Host "Done." -ForegroundColor Green
