// Deploy H-Series VM with InfiniBand using Azure Extension
// This Bicep template creates an H-series VM and automatically installs InfiniBand drivers
// using the Microsoft.HpcCompute/InfiniBandDriverWindows extension

@description('Prefix for all resource names')
param resourcePrefix string = 'hseries-ib'

@description('Location for all resources')
param location string = resourceGroup().location

@description('VM size - must be InfiniBand-capable H-series')
@allowed([
  'Standard_HC44rs'
  'Standard_HC44-16rs'
  'Standard_HC44-32rs'
  'Standard_HB120rs_v3'
  'Standard_HB120-16rs_v3'
  'Standard_HB120-32rs_v3'
  'Standard_HB120-64rs_v3'
  'Standard_HB176rs_v4'
  'Standard_HB60rs'
  'Standard_ND40rs_v2'
])
param vmSize string = 'Standard_HC44-16rs'

@description('Administrator username')
param adminUsername string = 'azureuser'

@description('Administrator password')
@secure()
param adminPassword string

@description('Number of VMs to deploy')
@minValue(1)
@maxValue(10)
param vmCount int = 1

// Variables
var vnetName = '${resourcePrefix}-vnet'
var subnetName = '${resourcePrefix}-subnet'
var nsgName = '${resourcePrefix}-nsg'
var publicIpName = '${resourcePrefix}-pip'
var nicName = '${resourcePrefix}-nic'
var vmName = '${resourcePrefix}-vm'

// Network Security Group with InfiniBand/RDMA rules
resource networkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: nsgName
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowRDP'
        properties: {
          priority: 1000
          access: 'Allow'
          direction: 'Inbound'
          destinationPortRange: '3389'
          protocol: 'Tcp'
          sourcePortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'AllowWinRM'
        properties: {
          priority: 1001
          access: 'Allow'
          direction: 'Inbound'
          destinationPortRange: '5985-5986'
          protocol: 'Tcp'
          sourcePortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'AllowInfiniBand'
        properties: {
          priority: 1100
          access: 'Allow'
          direction: 'Inbound'
          destinationPortRange: '*'
          protocol: '*'
          sourcePortRange: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'VirtualNetwork'
        }
      }
    ]
  }
}

// Virtual Network optimized for InfiniBand
resource virtualNetwork 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: '10.0.1.0/24'
          networkSecurityGroup: {
            id: networkSecurityGroup.id
          }
        }
      }
    ]
  }
}

// Public IP addresses for each VM
resource publicIpAddress 'Microsoft.Network/publicIPAddresses@2023-09-01' = [for i in range(0, vmCount): {
  name: '${publicIpName}${i + 1}'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: '${resourcePrefix}${i + 1}-${uniqueString(resourceGroup().id)}'
    }
  }
}]

// Network Interfaces with Accelerated Networking enabled (required for InfiniBand)
resource networkInterface 'Microsoft.Network/networkInterfaces@2023-09-01' = [for i in range(0, vmCount): {
  name: '${nicName}${i + 1}'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: publicIpAddress[i].id
          }
          subnet: {
            id: virtualNetwork.properties.subnets[0].id
          }
        }
      }
    ]
    enableAcceleratedNetworking: true  // Required for InfiniBand
  }
}]

// H-Series Virtual Machines
resource virtualMachine 'Microsoft.Compute/virtualMachines@2023-09-01' = [for i in range(0, vmCount): {
  name: '${vmName}${i + 1}'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: '${vmName}${i + 1}'
      adminUsername: adminUsername
      adminPassword: adminPassword
      windowsConfiguration: {
        enableAutomaticUpdates: true
        provisionVMAgent: true
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: '2019-datacenter-gensecond'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: networkInterface[i].id
        }
      ]
    }
    securityProfile: {
      securityType: 'Standard'  // Required for HCS Family compatibility
    }
  }
  tags: {
    'azd-env-name': resourcePrefix
    purpose: 'hpc-infiniband'
    vmSize: vmSize
  }
}]

// InfiniBand Driver Extension - The key enhancement!
resource infiniBandExtension 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = [for i in range(0, vmCount): {
  parent: virtualMachine[i]
  name: 'installInfiniBandDriverWindows'
  location: location
  properties: {
    publisher: 'Microsoft.HpcCompute'
    type: 'InfiniBandDriverWindows'
    typeHandlerVersion: '1.5'
    autoUpgradeMinorVersion: true
    settings: {
      // Optional: Add specific settings if needed
    }
    protectedSettings: {
      // Optional: Add protected settings if needed
    }
  }
}]

// Optional: PowerShell extension for additional configuration
resource configurationExtension 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = [for i in range(0, vmCount): {
  parent: virtualMachine[i]
  name: 'configureRDMA'
  location: location
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'CustomScriptExtension'
    typeHandlerVersion: '1.10'
    autoUpgradeMinorVersion: true
    settings: {
      fileUris: []
      commandToExecute: 'powershell.exe -ExecutionPolicy Unrestricted -Command "Write-Host \'Configuring RDMA...\'; Enable-NetAdapterRdma -Name \'*\' -ErrorAction SilentlyContinue; Set-SmbClientConfiguration -EnableMultiChannel $true -Confirm:$false -ErrorAction SilentlyContinue; Set-SmbClientConfiguration -EnableBandwidthThrottling $false -Confirm:$false -ErrorAction SilentlyContinue; Write-Host \'RDMA configuration completed.\'"'
    }
  }
  dependsOn: [
    infiniBandExtension[i]
  ]
}]

// Outputs
output vmNames array = [for i in range(0, vmCount): virtualMachine[i].name]
output publicIpAddresses array = [for i in range(0, vmCount): publicIpAddress[i].properties.ipAddress]
output fqdns array = [for i in range(0, vmCount): publicIpAddress[i].properties.dnsSettings.fqdn]
output rdpConnections array = [for i in range(0, vmCount): 'mstsc /v:${publicIpAddress[i].properties.ipAddress}']

output deploymentSummary object = {
  resourceGroup: resourceGroup().name
  location: location
  vmSize: vmSize
  vmCount: vmCount
  vnetName: vnetName
  infiniBandEnabled: true
  acceleratedNetworking: true
  extensions: [
    'InfiniBandDriverWindows v1.5'
    'RDMA Configuration'
  ]
}
