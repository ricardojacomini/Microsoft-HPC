param keyVaultName string
param principalId string
// Optional role GUID to assign. Default is Key Vault Contributor.
param roleDefinitionId string = 'f25e0fa2-a7c8-4377-a976-54943a77a395'
// Optional principal type: ServicePrincipal, User, Group. If empty, omit property so Azure infers it.
param principalType string = ''

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

// Build the properties object and include principalType only when provided.
var roleAssignmentProperties = union({
  roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)
  principalId: principalId
}, principalType != '' ? { principalType: principalType } : {})

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  // Make assignment name unique per role and principal
  name: guid(resourceGroup().id, keyVaultName, principalId, roleDefinitionId)
  scope: keyVault
  properties: roleAssignmentProperties
}

output roleAssignmentId string = roleAssignment.id
