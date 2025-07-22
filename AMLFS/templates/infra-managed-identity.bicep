targetScope = 'resourceGroup'

// AMLFS template with User-Assigned Managed Identity
param fsname string = 'amlfs'
param location string = resourceGroup().location
param vnet_name string = 'vnet'
param vnet_cidr string = '10.242.0.0/23'
param vnet_main string = 'main'
param vnet_main_cidr string = '10.242.0.0/24'
param vnet_amlfs string = 'amlfs'
param vnet_amlfs_cidr string = '10.242.1.0/24'
param storage_name string = 'storage${uniqueString(resourceGroup().id)}'
param managedIdentityName string = 'amlfs-identity-${uniqueString(resourceGroup().id)}'

// Zone configuration - can be overridden during deployment
@description('Availability zone for AMLFS deployment. Use single zone number (1, 2, or 3).')
param availabilityZone int = 2

// Create User-Assigned Managed Identity
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: managedIdentityName
  location: location
}

// Assign Storage Blob Data Contributor role to the managed identity on the storage account
resource storageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, managedIdentity.id, 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Assign Storage Account Contributor role to the managed identity on the storage account
resource storageAccountRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, managedIdentity.id, '17d1049b-9a84-46fb-8f53-869881c3d3ab')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '17d1049b-9a84-46fb-8f53-869881c3d3ab') // Storage Account Contributor
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource commonNsg 'Microsoft.Network/networkSecurityGroups@2023-05-01' = {
  name: 'nsg-common'
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowLustreTraffic'
        properties: {
          protocol: 'TCP'
          sourcePortRange: '*'
          destinationPortRanges: [
            '988'
            '1019'
          ]
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowLustreTrafficOutbound'
        properties: {
          protocol: 'TCP'
          sourcePortRange: '*'
          destinationPortRanges: [
            '988'
            '1019'
          ]
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 100
          direction: 'Outbound'
        }
      }
    ]
  }
}

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: vnet_name
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnet_cidr
      ]
    }
    subnets: [
      {
        name: vnet_main
        properties: {
          addressPrefix: vnet_main_cidr
          networkSecurityGroup: {
            id: commonNsg.id
          }
        }
      }
      {
        name: vnet_amlfs
        properties: {
          addressPrefix: vnet_amlfs_cidr
          networkSecurityGroup: {
            id: commonNsg.id
          }
          delegations: [
            {
              name: 'Microsoft.StorageCache.amlFileSystems'
              properties: {
                serviceName: 'Microsoft.StorageCache/amlFileSystems'
              }
            }
          ]
        }
      }
    ]
  }
}

resource amlfsSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-05-01' existing = {
  parent: virtualNetwork
  name: vnet_amlfs
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storage_name
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    publicNetworkAccess: 'Enabled'
    allowSharedKeyAccess: false  // Enhanced security - disable key access
    networkAcls: {
      defaultAction: 'Allow'
    }
    encryption: {
      services: {
        blob: {
          enabled: true
        }
        file: {
          enabled: true
        }
      }
      keySource: 'Microsoft.Storage'
    }
  }
  
  resource blobService 'blobServices' = {
    name: 'default'
    
    resource container 'containers' = {
      name: 'amlfs-data'
      properties: {
        publicAccess: 'None'
      }
    }
  }
}

resource fileSystem 'Microsoft.StorageCache/amlFileSystems@2023-05-01' = {
  name: fsname
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  zones: [ string(availabilityZone) ]  // Move zones to top level
  sku: {
    name: 'AMLFS-Durable-Premium-250'
  }
  properties: {
    storageCapacityTiB: 8
    filesystemSubnet: amlfsSubnet.id
    maintenanceWindow: {
      dayOfWeek: 'Friday'
      timeOfDayUTC: '23:00'  // Use timeOfDayUTC instead of timeOfDay
    }
    // Simplified AMLFS without HSM to avoid configuration issues
    // HSM can be configured post-deployment if needed
  }
  dependsOn: [
    storageRoleAssignment
    storageAccountRoleAssignment
  ]
}

output fsname string = fsname
output resource_group_name string = resourceGroup().name
output location string = location
output subnet_id string = amlfsSubnet.id
output lustre_id string = fileSystem.id
output lustre_client_info object = fileSystem.properties.clientInfo  // Use clientInfo instead of mgsAddress
output managedIdentityId string = managedIdentity.id
output managedIdentityPrincipalId string = managedIdentity.properties.principalId
output storageAccountName string = storageAccount.name
output containerName string = storageAccount::blobService::container.name
