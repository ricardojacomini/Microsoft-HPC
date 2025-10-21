param prefix string
param workSpaceName string
param location string = resourceGroup().location

@description('Optional pre-hosted script URI (including SAS) to use instead of inlining the script content')
param primaryScriptUri string = ''

@description('Optional array of supporting script URIs (zip files or additional scripts)')
param supportingScriptUris array = []

resource workSpace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: workSpaceName
}

resource userMiForScript 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${prefix}userMiForScript'
  location: location
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(userMiForScript.id, 'Contributor')
  scope: workSpace
  properties: {
    //Contributor role
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c')
    principalId: userMiForScript.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

//NOTE: The Deployment Script depends on an internally-created storage account and the shared-key-based access.
resource createTable 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: '${prefix}createTable'
  location: location
  kind: 'AzurePowerShell'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userMiForScript.id}': {}
    }
  }
  properties: {
  azPowerShellVersion: '11.0'
    cleanupPreference: 'OnExpiration'
    retentionInterval: 'PT1H'
    // Prefer a pre-hosted primaryScriptUri (includes SAS) when provided. Otherwise fall back to inlining the script content.
    scriptContent: primaryScriptUri == '' ? loadTextContent('custom-la-table.ps1') : ''
    primaryScriptUri: primaryScriptUri
    supportingScriptUris: (length(supportingScriptUris) > 0) ? supportingScriptUris : []
    arguments: workSpace.id
  }
  dependsOn: [
    roleAssignment
  ]
}
