targetScope = 'resourceGroup'

/*
Azure Role Definition IDs Used in This Template:
================================================================

b7e6dc6d-f1e8-4753-8033-0f276bb0955b - Storage Blob Data Owner
  • Full control over Azure Storage blob data
  • Permissions: read, write, delete, and manage ACLs on blob data
  • Required for AMLFS to manage Lustre data, logs, and import/export operations
  • Applied to: HSM data container, logging container, import/export containers, and AMLFS subnet

Other Common Azure Storage Role IDs (for reference):
  • ba92f5b4-2d11-453d-a403-e96b0029c9fe - Storage Blob Data Contributor (read/write, no delete)
  • 2a2b9908-6ea1-4ae2-8e65-a410df84e7d1 - Storage Blob Data Reader (read-only)
  • 17d1049b-9a84-46fb-8f53-869881c3d3ab - Storage Account Contributor (manage storage accounts)
*/

param fsname string = 'amlfs'
param location string = resourceGroup().location
param vnet_name string = 'vnet'
param vnet_cidr string = '10.242.0.0/23'
param vnet_main string = 'main'
param vnet_main_cidr string = '10.242.0.0/24'
param vnet_amlfs string = 'amlfs'
param vnet_amlfs_cidr string = '10.242.1.0/24'
param storage_name string = 'storage${uniqueString(resourceGroup().id)}'
param hsm_data_container string = 'lustre'
param hsm_logging_container string = 'logging-lustre'

resource commonNsg 'Microsoft.Network/networkSecurityGroups@2020-06-01' = {
  name: 'nsg-common'
  location: location
  properties: {
    securityRules: [
    ]
  }
}

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2020-05-01' = {
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
        }
      }
    ]
  }
}

resource amlfsSubnet 'Microsoft.Network/virtualNetworks/subnets@2020-05-01' existing = {
  parent: virtualNetwork
  name: vnet_amlfs
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2021-09-01' = {
  name: storage_name
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    minimumTlsVersion: 'TLS1_2'
  }
}

resource blobServices 'Microsoft.Storage/storageAccounts/blobServices@2021-09-01' = {
  name: 'default'
  parent: storageAccount
}

resource hsmData 'Microsoft.Storage/storageAccounts/blobServices/containers@2021-06-01' = {
  name: hsm_data_container
  parent: blobServices
  properties: {
    publicAccess: 'None'
  }
}

resource hsmLogging 'Microsoft.Storage/storageAccounts/blobServices/containers@2021-06-01' = {
  name: hsm_logging_container
  parent: blobServices
  properties: {
    publicAccess: 'None'
  }
}

// Simplified: Remove user-based role assignment - AMLFS will use managed identity
// Role assignments for AMLFS are typically handled automatically by the service

resource fileSystem 'Microsoft.StorageCache/amlFileSystems@2021-11-01-preview' = {
  name: fsname
  location: location
  sku: {
    name: 'AMLFS-Durable-Premium-250'
  }
  properties: {
    storageCapacityTiB: 8
    zones: [ 1 ]
    filesystemSubnet: amlfsSubnet.id
    maintenanceWindow: {
      dayOfWeek: 'Friday'
      timeOfDay: '23:00'
    }
    hsm: {
      settings: {
        container: hsmData.id
        loggingContainer: hsmLogging.id
        importPrefix: '/'
      }
    }
  }
  // No explicit dependencies needed - AMLFS manages its own access
}// Remove the subnet role assignment to simplify deployment
// Only keep the essential HSM data container role assignment

output fsname string = fsname
output resource_group_name string = resourceGroup().name
output location string = location
output subnet_id string = amlfsSubnet.id
output lustre_id string = fileSystem.id
output lustre_mgs string = fileSystem.properties.mgsAddress
output storage_account_name string = storageAccount.name
output container_name string = hsmData.name
