import { CertificateSettings } from 'types-and-vars.bicep'

param vaultNamePrefix string?
param location string = resourceGroup().location
// Optional: principal objectId to receive the Certificates Officer role. If empty, use the managed identity created here.
param certOfficerPrincipalId string = ''
// Optional: resourceId of an existing storage account to host deployment script files.
// Example: resourceId('Microsoft.Storage/storageAccounts', 'mystorageacct')
// Optional: existing storage account used by Deployment Script for logs/blobs.
param storageAccountName string = ''
// If empty, storage account is assumed to be in the same resource group as the deployment.
// storageAccountResourceGroup removed; deployment script will assume storage account is in the current resource group when provided.

var suffix = uniqueString(resourceGroup().id)
// Ensure a non-empty suffix for names used in container group to satisfy analyzers
var containerGroupSuffix = length(suffix) > 0 ? substring(suffix, 0, 13) : 'x'

/*
 * NOTE
 *
 * A valid vault name must:
 * 1. Be globally unique
 * 2. Be of length 3-24
 * 3. Start with a letter and end with a letter or digit
 * 4. Not contain consecutive hyphens
 */
var prefix = vaultNamePrefix ?? '${resourceGroup().name}-kv'

// Build a candidate and then sanitize it to avoid trailing hyphens or consecutive hyphens
var vaultCandidateRaw = take('${prefix}-${suffix}', 24)
// If the candidate ends with a hyphen, trim the trailing hyphen
var vaultCandidateTrimmed = endsWith(vaultCandidateRaw, '-') ? substring(vaultCandidateRaw, 0, length(vaultCandidateRaw) - 1) : vaultCandidateRaw
// Replace any accidental consecutive hyphens with a single hyphen
var vaultCandidateNoDouble = replace(vaultCandidateTrimmed, '--', '-')
// Normalize to lowercase (Key Vault names are case-insensitive) and use as final vault name
var vaultName = toLower(vaultCandidateNoDouble)

var rgName = resourceGroup().name

resource keyVault 'Microsoft.KeyVault/vaults@2024-04-01-preview' = {
  name: vaultName
  location: location
  properties: {
    sku: {
      name: 'standard'
      family: 'A'
    }
    tenantId: tenant().tenantId
    accessPolicies: []
    enabledForDeployment: true
    enabledForDiskEncryption: true
    enabledForTemplateDeployment: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enableRbacAuthorization: true
    publicNetworkAccess: 'Enabled'
  }
}

resource userMiForNewCert 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'userMiForNewCert'
  location: location
}

// Assign roles to the managed identity that will create the certificate.
// We assign both Key Vault Administrator and Key Vault Certificates Officer.
module assignKeyVaultAdmin './key-vault-role-assignment.bicep' = {
  name: 'assignKeyVaultAdmin'
  params: {
    keyVaultName: vaultName
    principalId: userMiForNewCert.properties.principalId
    roleDefinitionId: '00482a5a-887f-4fb3-b363-3b7fe8e74483'
  }
  dependsOn: [
    keyVault
  ]
}

module assignKeyVaultCertificatesOfficer './key-vault-role-assignment-flexible.bicep' = {
  name: 'assignKeyVaultCertificatesOfficer'
  params: {
    keyVaultName: vaultName
    // Allow overriding the principal; fall back to the managed identity's principalId when param is empty
    principalId: empty(certOfficerPrincipalId) ? userMiForNewCert.properties.principalId : certOfficerPrincipalId
    roleDefinitionId: 'a4417e6f-fecd-4de8-b567-7b0420556985'
    // Leave principalType empty so Azure infers it (avoids UnmatchedPrincipalType errors)
    principalType: ''
  }
  dependsOn: [
    keyVault
  ]
}

// Conditional reference to an existing storage account (if provided)
// Assign Storage Blob Data Contributor to the managed identity on the storage account so Deployment Script can use ManagedIdentity auth

// Optional Storage Account reference
var storageBlobDataContributorRoleId = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'

resource storageAccountExisting 'Microsoft.Storage/storageAccounts@2023-01-01' existing = if (storageAccountName != '') {
  name: storageAccountName
}

resource assignStorageBlobContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (storageAccountName != '') {
  name: guid(resourceGroup().id, storageAccountExisting.id, userMiForNewCert.id, storageBlobDataContributorRoleId)
  scope: storageAccountExisting
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataContributorRoleId)
    principalId: userMiForNewCert.properties.principalId
    // omit principalType so Azure infers it
  }
}

// Build deployment script properties and include storageAccountSettings when a storage account is provided
// deployment script helper variables removed; we emit properties inline below for clarity.

param certName string = 'newCert'
param commonName string = 'HPC Pack Node Communication'
@description('If provided, a pre-generated blob URL (including SAS token) that points to KeyVaultCertificate.ps1')
param primaryScriptUri string = ''
@description('Optional array of supporting script URIs (zip files or additional scripts) available to the deployment script')
param supportingScriptUris array = []

@description('Name of the storage container where supporting scripts and zips are uploaded (default: scripts)')
param containerName string = 'scripts'

@secure()
@description('Optional storage account key (base64). If you can provide a storage account key, the deploymentScript can use it to write outputs. Note: passing a user-delegation SAS in storageAccountSettings is not supported by the current schema; primaryScriptUri can include a SAS for script download but outputs typically require account key. If you cannot supply a key, consider creating the certificate natively or running the script from CI/pipeline.')
param storageAccountKey string = ''

resource newCertOfficer 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'newCertKeyVaultCertificatesOfficer'
  location: location
  kind: 'AzurePowerShell'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userMiForNewCert.id}': {}
    }
  }
  properties: {
    azPowerShellVersion: '11.0'
    cleanupPreference: 'OnExpiration'
    retentionInterval: 'PT1H'
    scriptContent: loadTextContent('KeyVaultCertificate.ps1')
    // Provide a deterministic container group name to avoid platform-generated names
    // and reduce chance of collisions. Lowercase and truncate to 63 chars to
    // satisfy common name length limits for container groups.
    // containerSettings: {
    //   // Use the computed non-empty suffix and a short prefix.
    //   containerGroupName: containerName // toLower(format('scripts-{0}', containerGroupSuffix))
      
    // }
    // // If you supplied `primaryScriptUri` the service will fetch the script from that blob URL (include SAS in the URL).
    // // Otherwise the template will attempt to upload the inline script content (not recommended when allowSharedKeyAccess=false).
    // primaryScriptUri: primaryScriptUri
    // supportingScriptUris: (length(supportingScriptUris) > 0) ? supportingScriptUris : []
    // // Provide storage settings when a storageAccountName and storageAccountKey are supplied.
    // // Note: the Deployment Script API expects a storageAccountKey (account key) in storageAccountSettings.
    // // If your environment forbids account keys (allowSharedKeyAccess = false), this field cannot be used and
    // // deploymentScripts will still fail when attempting to write outputs. In that case prefer the native Key Vault
    // // certificate resource or run the script from your CI/CD pipeline or a managed function/runbook.
    // storageAccountSettings: (storageAccountName != '' && storageAccountKey != '') ? {
    //   storageAccountName: storageAccountName
    //   storageAccountKey: storageAccountKey
    // } : {}
    arguments: '-VaultName ${vaultName} -Name ${certName} -ResourceGroup ${rgName} -Location ${location} -CommonName "${commonName}"'
    // storageAccountSettings intentionally omitted. If you require a storage account for the deployment script,
    // declare it and supply a valid StorageAccountConfiguration (storageAccountName / storageAccountKey) per API schema.
  }
  dependsOn: [ 
    assignKeyVaultAdmin
    assignKeyVaultCertificatesOfficer
    assignStorageBlobContributor
  ]
}

output certSettings CertificateSettings = {
  thumbprint: newCertOfficer.properties.outputs.thumbprint
  url: newCertOfficer.properties.outputs.url
  vaultName: vaultName
  vaultResourceGroup: rgName
}

// Helpful validation output: if both primaryScriptUri and storageAccountKey are empty, caller likely needs
// to either provide a script URI+SAS or run the script outside of deploymentScripts (CI/pipeline) or provide the storage account key.
// Fail early with a clear message if neither a primary script URI nor a storage account key was provided.
// This prevents confusing runtime failures when deploymentScripts cannot write outputs because shared-key auth is disallowed.
output deploymentScriptHint object = {
  primaryScriptUriProvided: primaryScriptUri != ''
  // Avoid referencing secure parameters in outputs (would trigger secret-in-outputs warnings).
  // We only indicate whether a primary script URI was provided. If not, callers should
  // ensure they supply a storage account key or use an alternate approach (native cert or CI).
  advice: primaryScriptUri == '' ? 'No primaryScriptUri provided; ensure you either supply a storageAccountKey at deployment time or use a native key vault certificate/CI workflow.' : 'ok'
}

// Conditional enforcement: invoke module that intentionally fails when
// neither primaryScriptUri nor storageAccountKey are supplied. This
// provides a template-time guard (user requested option C).
module enforcePrimaryScriptOrKeyModule './modules/enforcePrimaryScriptOrKey.bicep' = if (primaryScriptUri == '' && storageAccountKey == '') {
  name: 'enforcePrimaryScriptOrKeyModule'
}
