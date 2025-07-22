targetScope = 'resourceGroup'

// Basic AMLFS template - no HSM
param fsname string = 'amlfs'
param location string = resourceGroup().location
param vnet_name string = 'vnet'
param vnet_cidr string = '10.242.0.0/23'
param vnet_main string = 'main'
param vnet_main_cidr string = '10.242.0.0/24'
param vnet_amlfs string = 'amlfs'
param vnet_amlfs_cidr string = '10.242.1.0/24'
param storage_name string = 'storage${uniqueString(resourceGroup().id)}'

// Zone configuration - can be overridden during deployment
@description('Availability zone for AMLFS deployment. Use single zone number (1, 2, or 3).')
param availabilityZone int = 2

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

resource fileSystem 'Microsoft.StorageCache/amlFileSystems@2021-11-01-preview' = {
  name: fsname
  location: location
  sku: {
    name: 'AMLFS-Durable-Premium-250'
  }
  properties: {
    storageCapacityTiB: 8
    zones: [ availabilityZone ]  // Use parameter for dynamic zone selection
    filesystemSubnet: amlfsSubnet.id
    maintenanceWindow: {
      dayOfWeek: 'Friday'
      timeOfDay: '23:00'
    }
    // No HSM - basic AMLFS only
  }
}

output fsname string = fsname
output resource_group_name string = resourceGroup().name
output location string = location
output subnet_id string = amlfsSubnet.id
output lustre_id string = fileSystem.id
output lustre_mgs string = fileSystem.properties.mgsAddress
output storage_account_name string = storageAccount.name

