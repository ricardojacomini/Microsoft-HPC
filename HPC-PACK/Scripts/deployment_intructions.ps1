$region = 'eastus'
$resourceGroup = 'HPC-PACK-Jacomini-23'
$principalId = az ad signed-in-user show --query id --output tsv

az group create --name $resourceGroup --location $region

# storage account & container to host the zips (adjust as needed)
$rawSa = "sa-$($region)-$($resourceGroup)"
# Storage account names must be 3-24 chars, lowercase, alphanumeric only.
$storageAccountName = ($rawSa.ToLower() -replace '[^a-z0-9]', '')
if ($storageAccountName.Length -gt 24) { $storageAccountName = $storageAccountName.Substring(0,24) }
if ($storageAccountName.Length -lt 3) { $storageAccountName = ($storageAccountName + 'sa000').Substring(0,3) }
Write-Host "Using storage account name: $storageAccountName"
# container and expiry settings
$containerName = 'scripts'

# SAS expiry days (used for PS1s and zip uploads)
$expiryDays = 7
# List of local PS1 files to upload (adjust paths as needed)
$localPS1s = @(
    'deploy\bicep\shared\KeyVaultCertificate.ps1'
    'deploy\bicep\shared\custom-la-table.ps1'
)

# Local ZIP files to upload (use full paths or relative to repo)
$localZips = @(
  'deploy\bicep\Generated\ConfigDBPermissions.ps1.zip'
  'deploy\bicep\Generated\ConfigSQLServer.ps1.zip'
  'deploy\bicep\Generated\CreateADPDC.ps1.zip'
  'deploy\bicep\Generated\CreateADPDC-fixed.ps1.zip'
  'deploy\bicep\Generated\InstallHpcNode.ps1.zip'
  'deploy\bicep\Generated\InstallPrimaryHeadNode.ps1.zip'
  'deploy\bicep\Generated\JoinADDomain.ps1.zip'
)

# Ensure storage account exists (create if missing)
try {
    az storage account show --name $storageAccountName --resource-group $resourceGroup > $null 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Storage account $storageAccountName not found in resource group $resourceGroup. Creating..."
        az storage account create --name $storageAccountName --resource-group $resourceGroup --location $region --sku Standard_LRS | Out-Null
    } else {
        Write-Host "Storage account $storageAccountName already exists."
    }
} catch {
    Write-Warning "Unable to determine storage account existence via az; proceeding and letting commands fail if necessary."
}

# Ensure container exists before uploading PS1s
Write-Host "Ensuring container '$containerName' exists in storage account $storageAccountName..."
az storage container create --account-name $storageAccountName --name $containerName --auth-mode login | Out-Null

# Upload each PS1 and generate SAS URLs
$ps1Urls = @()
foreach ($ps1 in $localPS1s) {
    if (-not (Test-Path $ps1)) {
        Write-Warning "PS1 not found, skipping: $ps1"
        continue
    }

    $ps1Name = [System.IO.Path]::GetFileName($ps1)
    Write-Host "Uploading PS1 $ps1 -> $storageAccountName/$containerName/$ps1Name ..."
    az storage blob upload --account-name $storageAccountName --container-name $containerName --name $ps1Name --file $ps1 --auth-mode login | Out-Null

    # Generate SAS for the PS1
    $expiry = (Get-Date).ToUniversalTime().AddDays($expiryDays).ToString('yyyy-MM-ddTHH:mmZ')
    $sasPs1 = az storage blob generate-sas --account-name $storageAccountName --container-name $containerName --name $ps1Name --permissions r --expiry $expiry --auth-mode login --https-only --output tsv
    if (-not $sasPs1) { Write-Warning "Failed to generate SAS for $ps1Name"; continue }
    $ps1Url = "https://$($storageAccountName).blob.core.windows.net/$containerName/$ps1Name`?$sasPs1"
    $ps1Urls += $ps1Url
}

# Choose primaryScriptUri: prefer KeyVaultCertificate.ps1 if present, otherwise first PS1
$primaryScriptUri = $null
if ($ps1Urls.Count -gt 0) {
    $preferred = $ps1Urls | Where-Object { $_ -like '*KeyVaultCertificate.ps1*' } | Select-Object -First 1
    if ($preferred) { $primaryScriptUri = $preferred } else { $primaryScriptUri = $ps1Urls[0] }
    Write-Host "Selected primaryScriptUri: $primaryScriptUri"
} else {
    Write-Warning "No PS1 uploads produced a primaryScriptUri. You may need to run helper manually or check paths."
}

# Upload and generate SAS for each zip
$sasUrls = @()
foreach ($localPath in $localZips) {
    if (-not (Test-Path $localPath)) {
        Write-Warning "Local file not found, skipping: $localPath"
        continue
    }

    $blobName = [System.IO.Path]::GetFileName($localPath)
    Write-Host "Uploading $localPath -> $storageAccountName/$containerName/$blobName ..."
    az storage blob upload --account-name $storageAccountName --container-name $containerName --name $blobName --file $localPath --auth-mode login | Out-Null

    # Generate user-delegation SAS (auth-mode login)
    $expiry = (Get-Date).ToUniversalTime().AddDays($expiryDays).ToString('yyyy-MM-ddTHH:mmZ')
    $sas = az storage blob generate-sas `
        --account-name $storageAccountName `
        --container-name $containerName `
        --name $blobName `
        --permissions r `
        --expiry $expiry `
        --auth-mode login `
        --https-only `
        --output tsv

    if (-not $sas) {
        Write-Warning "Failed to generate SAS for $blobName"
        continue
    }

    $url = "https://$($storageAccountName).blob.core.windows.net/$containerName/$blobName`?${sas}"
    $sasUrls += $url
}

if ($sasUrls.Count -eq 0) {
    throw "No SAS URLs produced. Aborting deployment."
}

Write-Host "`nGenerated SAS URLs:"
$sasUrls | ForEach-Object { Write-Host $_ }

# Combine remaining PS1 URLs (exclude primary) and zip SAS URLs into supporting URIs
$supporting = @()
if ($ps1Urls.Count -gt 0) {
    $supporting += ($ps1Urls | Where-Object { $_ -ne $primaryScriptUri })
}
$supporting += $sasUrls

# Convert to compact JSON array for az CLI parameter passing
$urisJson = $supporting | ConvertTo-Json -Compress

# Option A: Pass as a parameter named `supportingScriptUris` to the deployment
# (many templates accept this for deploymentScripts supporting files).
# If your template uses a different parameter name, change `supportingScriptUris` below.

az deployment group create `
    --resource-group $resourceGroup `
    --template-file "vault-1hn-wincn-ad.json" `
    --parameters "@parametersFile.json" `
    --parameters certOfficerPrincipalId=$principalId primaryScriptUri="$primaryScriptUri" supportingScriptUris="$urisJson" storageAccountName=$storageAccountName

# --- End