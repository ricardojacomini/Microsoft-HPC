<#
.Synopsis
    Create or import a new Azure Key Vault Certificate for HPC Pack Cluster

.DESCRIPTION
    This script creates or imports an Azure Key Vault certificate used by the HPC Pack Cluster deployment.
    It will create the resource group and Key Vault if they do not exist.
    The script is safe to run under user, service principal, or managed identity contexts. It emits a compact JSON
    object with 'thumbprint' and 'url' for use with Deployment Scripts.
#>
[CmdletBinding(DefaultParameterSetName = 'CreateNewCertificate')]
param(
    [Parameter(Mandatory = $true)]
    [string] $VaultName,

    [Parameter(Mandatory = $true)]
    [string] $Name,

    [Parameter(Mandatory = $true)]
    [string] $ResourceGroup,

    [Parameter(Mandatory = $true)]
    [string] $Location,

    [Parameter(Mandatory = $false)]
    [string] $Subscription = '',

    [Parameter(Mandatory = $false)]
    [string] $CommonName = 'HPC Pack Node Communication',

    [Parameter(Mandatory = $true, ParameterSetName = 'ImportPfxCertificate')]
    [string] $PfxFilePath,

    [Parameter(Mandatory = $true, ParameterSetName = 'ImportPfxCertificate')]
    [System.Security.SecureString] $Password
)

Write-Host "Validating input parameters..." -ForegroundColor Green
[System.Net.ServicePointManager]::SecurityProtocol = 'tls,tls11,tls12'
$azContext = Get-AzContext -ErrorAction Stop
if ($Subscription) {
    if (($azContext.Subscription.Name -ne $Subscription) -and ($azContext.Subscription.Id -ne $Subscription)) {
        Set-AzContext -Subscription $Subscription -ErrorAction Stop
    }
} else {
    Write-Verbose "No subscription specified; using current subscription $($azContext.Subscription.Name)"
}

if ($PfxFilePath) {
    try { $pfxCert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 -ArgumentList $PfxFilePath, $Password } 
    catch [System.Management.Automation.MethodInvocationException] { throw $_.Exception.InnerException }
    $pfxCert.Dispose()
}

# Normalize location early: remove whitespace and convert to lowercase
$Location = ($Location -replace '\s+', '').ToLower()

# Ensure resource group
$rg = Get-AzResourceGroup -Name $ResourceGroup -Location $Location -ErrorAction SilentlyContinue
if ($null -eq $rg) {
    Write-Host "Creating resource group '$ResourceGroup' in location '$Location'" -ForegroundColor Green
    $rg = New-AzResourceGroup -Name $ResourceGroup -Location $Location
}

# Ensure Key Vault
$keyVault = Get-AzKeyVault -VaultName $VaultName -ErrorAction SilentlyContinue
if ($keyVault) {
    Write-Host "Key Vault '$VaultName' already exists." -ForegroundColor Green
    if ($keyVault.Location -ne $Location) { throw "The Key Vault '$VaultName' exists in another location ($($keyVault.Location))." }
    if ($keyVault.ResourceGroupName -ne $ResourceGroup) { throw "The Key Vault '$VaultName' exists in another resource group ($($keyVault.ResourceGroupName))." }
    if (-not $keyVault.EnabledForDeployment -or -not $keyVault.EnabledForTemplateDeployment) {
        Write-Host "Enabling EnabledForDeployment and EnabledForTemplateDeployment for Key Vault '$VaultName'" -ForegroundColor Green
        Set-AzKeyVaultAccessPolicy -VaultName $VaultName -EnabledForDeployment -EnabledForTemplateDeployment -ErrorAction Stop
    }
} else {
    Write-Host "Creating Key Vault '$VaultName' in resource group '$ResourceGroup'" -ForegroundColor Green
    $keyVault = New-AzKeyVault -Name $VaultName -ResourceGroupName $ResourceGroup -Location $Location -EnabledForDeployment -EnabledForTemplateDeployment -ErrorAction Stop
}

if ($PSBoundParameters.ContainsKey('PfxFilePath')) {
    Write-Host "Importing PFX certificate to Key Vault '$VaultName' as '$Name'" -ForegroundColor Green
    $keyVaultCert = Import-AzKeyVaultCertificate -VaultName $VaultName -Name $Name -FilePath $PfxFilePath -Password $Password -ErrorAction Stop
} else {
    if ($CommonName.StartsWith('CN=')) { $subjectName = $CommonName } else { $subjectName = "CN=$CommonName" }
    Write-Host "Creating self-signed certificate '$Name' in Key Vault '$VaultName' (subject $subjectName)" -ForegroundColor Green
    $certPolicy = New-AzKeyVaultCertificatePolicy -SecretContentType 'application/x-pkcs12' -SubjectName $subjectName -IssuerName 'Self' -ValidityInMonths 60 -ReuseKeyOnRenewal -KeyUsage DigitalSignature, KeyAgreement, KeyEncipherment -Ekus '1.3.6.1.5.5.7.3.1','1.3.6.1.5.5.7.3.2'

    # Retry Add-AzKeyVaultCertificate to tolerate RBAC propagation delays
    $retryCount = 0
    do {
        try {
            $null = Add-AzKeyVaultCertificate -VaultName $VaultName -Name $Name -CertificatePolicy $certPolicy -ErrorAction Stop
            break
        } catch {
            if ($retryCount -ge 5) { throw $_ }
            Write-Verbose "Add-AzKeyVaultCertificate failed; retrying in 10s (attempt $($retryCount + 1) of 6)"
            Start-Sleep -Seconds 10
            $retryCount++
        }
    } while ($true)
    Write-Host 'Waiting for the certificate to be provisioned...' -ForegroundColor Green
    Start-Sleep -Seconds 5
    $keyVaultCert = Get-AzKeyVaultCertificate -VaultName $VaultName -Name $Name
    while (!$keyVaultCert.Thumbprint -or -not $keyVaultCert.SecretId) {
        Start-Sleep -Seconds 2
        $keyVaultCert = Get-AzKeyVaultCertificate -VaultName $VaultName -Name $Name
    }
}

Write-Host "Certificate created/imported. Emitting compact JSON output (thumbprint + url)." -ForegroundColor Yellow
"Vault Name           : $VaultName"
"Vault Resource Group : $ResourceGroup"
"Certificate URL      : $($keyVaultCert.SecretId)"
"Cert Thumbprint      : $($keyVaultCert.Thumbprint)"

$DeploymentScriptOutputs = @{ thumbprint = $keyVaultCert.Thumbprint; url = $keyVaultCert.SecretId }
$DeploymentScriptOutputs | ConvertTo-Json -Compress | Write-Output