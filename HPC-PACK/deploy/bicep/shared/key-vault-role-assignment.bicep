param keyVaultName string
param principalId string
// Optional role GUID to assign. Default is Key Vault Contributor.
param roleDefinitionId string = 'f25e0fa2-a7c8-4377-a976-54943a77a395'

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  // Make assignment name unique per role and principal
  name: guid(resourceGroup().id, keyVaultName, principalId, roleDefinitionId)
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}
