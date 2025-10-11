import { CertificateSettings } from 'types-and-vars.bicep'

param vaultNamePrefix string?
param scriptStorageAccountId string = '' // optional; resource id of a storage account for deployment script staging
param location string = resourceGroup().location

var suffix = uniqueString(resourceGroup().id)

/*
 * NOTE
 *
 * A valid vault name must:
 * 1. Be globally unique
 * 2. Be of length 3-24
 */
var prefix = vaultNamePrefix ?? '${resourceGroup().name}-kv'
var vaultName = take('${prefix}-${suffix}', 24)

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

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(userMiForNewCert.id, 'Contributor')
  scope: keyVault
  properties: {
    //Key Vault Administrator
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '00482a5a-887f-4fb3-b363-3b7fe8e74483')
    principalId: userMiForNewCert.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// If no scriptStorageAccountId is provided, create a dedicated staging storage account with shared key access enabled
resource newScriptStorage 'Microsoft.Storage/storageAccounts@2022-09-01' = if (scriptStorageAccountId == '') {
  name: take('hpcpackscripts${uniqueString(resourceGroup().id)}',24)
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    minimumTlsVersion: 'TLS1_2'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
  }
}

//NOTE: The Deployment Script depends on an internally-created storage account and the shared-key-based access.
resource newCert 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'newCert'
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
    scriptContent: loadTextContent('key-vault-with-cert.ps1')
    /*
     * NOTE
     * passing a string parameter for PS with space in between is problematic due to the problem of the Deployment Scripts. For example, if
     *
     * arguments: '-c "HPC Pack"'
     *
     * then the PS script only gets "HPC" for param "-c".
     */
    arguments: '-v ${vaultName}'
    storageAccountSettings: {
      storageAccountName: scriptStorageAccountId != '' ? last(split(scriptStorageAccountId, '/')) : newScriptStorage.name
    }
  }
  dependsOn: [
    roleAssignment
  ]
}

output certSettings CertificateSettings = {
  thumbprint: newCert.properties.outputs.thumbprint
  url: newCert.properties.outputs.url
  vaultName: vaultName
  vaultResourceGroup: rgName
}
