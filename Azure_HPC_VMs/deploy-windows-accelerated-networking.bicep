// Deploy Windows VM with Accelerated Networking
// This Bicep template creates regular Windows VMs with Accelerated Networking enabled
// Compatible with most VM sizes and provides significant network performance improvements

@description('Prefix for all resource names')
param resourcePrefix string = 'win-accel'

@description('Location for all resources')
param location string = resourceGroup().location

@description('VM size - most sizes support Accelerated Networking')
@allowed([
  // General Purpose (Accelerated Networking supported)
  'Standard_D2s_v3'
  'Standard_D4s_v3'
  'Standard_D8s_v3'
  'Standard_D16s_v3'
  'Standard_D32s_v3'
  'Standard_D48s_v3'
  'Standard_D64s_v3'
  // Compute Optimized
  'Standard_F2s_v2'
  'Standard_F4s_v2'
  'Standard_F8s_v2'
  'Standard_F16s_v2'
  'Standard_F32s_v2'
  'Standard_F48s_v2'
  'Standard_F64s_v2'
  'Standard_F72s_v2'
  // Memory Optimized
  'Standard_E2s_v3'
  'Standard_E4s_v3'
  'Standard_E8s_v3'
  'Standard_E16s_v3'
  'Standard_E32s_v3'
  'Standard_E48s_v3'
  'Standard_E64s_v3'
  // Latest Generation
  'Standard_D2s_v4'
  'Standard_D4s_v4'
  'Standard_D8s_v4'
  'Standard_D16s_v4'
  'Standard_D32s_v4'
  'Standard_D48s_v4'
  'Standard_D64s_v4'
  // V5 Series
  'Standard_D2s_v5'
  'Standard_D4s_v5'
  'Standard_D8s_v5'
  'Standard_D16s_v5'
  'Standard_D32s_v5'
  'Standard_D48s_v5'
  'Standard_D64s_v5'
])
param vmSize string = 'Standard_D4s_v3'

@description('Windows Server version')
@allowed([
  '2019-datacenter'
  '2019-datacenter-gensecond'
  '2022-datacenter'
  '2022-datacenter-azure-edition'
  '2022-datacenter-azure-edition-core'
  '2022-datacenter-core'
  '2022-datacenter-core-g2'
])
param windowsOSVersion string = '2022-datacenter-azure-edition'

@description('Administrator username')
param adminUsername string = 'azureuser'

@description('Administrator password')
@secure()
param adminPassword string

@description('Number of VMs to deploy')
@minValue(1)
@maxValue(20)
param vmCount int = 1

@description('Enable premium storage (SSD)')
param enablePremiumStorage bool = true

@description('OS disk size in GB')
@minValue(128)
@maxValue(2048)
param osDiskSizeGB int = 128

// Variables
var vnetName = '${resourcePrefix}-vnet'
var subnetName = '${resourcePrefix}-subnet'
var nsgName = '${resourcePrefix}-nsg'
var publicIpName = '${resourcePrefix}-pip'
var nicName = '${resourcePrefix}-nic'
var vmName = '${resourcePrefix}-vm'
var storageAccountType = enablePremiumStorage ? 'Premium_LRS' : 'StandardSSD_LRS'

// Check if VM size supports Accelerated Networking
var acceleratedNetworkingSizes = [
  'Standard_D2s_v3', 'Standard_D4s_v3', 'Standard_D8s_v3', 'Standard_D16s_v3', 'Standard_D32s_v3', 'Standard_D48s_v3', 'Standard_D64s_v3'
  'Standard_D2s_v4', 'Standard_D4s_v4', 'Standard_D8s_v4', 'Standard_D16s_v4', 'Standard_D32s_v4', 'Standard_D48s_v4', 'Standard_D64s_v4'
  'Standard_D2s_v5', 'Standard_D4s_v5', 'Standard_D8s_v5', 'Standard_D16s_v5', 'Standard_D32s_v5', 'Standard_D48s_v5', 'Standard_D64s_v5'
  'Standard_F2s_v2', 'Standard_F4s_v2', 'Standard_F8s_v2', 'Standard_F16s_v2', 'Standard_F32s_v2', 'Standard_F48s_v2', 'Standard_F64s_v2', 'Standard_F72s_v2'
  'Standard_E2s_v3', 'Standard_E4s_v3', 'Standard_E8s_v3', 'Standard_E16s_v3', 'Standard_E32s_v3', 'Standard_E48s_v3', 'Standard_E64s_v3'
]
var supportsAcceleratedNetworking = contains(acceleratedNetworkingSizes, vmSize)

// Network Security Group with optimized rules
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
        name: 'AllowHTTPS'
        properties: {
          priority: 1002
          access: 'Allow'
          direction: 'Inbound'
          destinationPortRange: '443'
          protocol: 'Tcp'
          sourcePortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'AllowInternalTraffic'
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

// Virtual Network optimized for high performance
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

// Network Interfaces with Accelerated Networking
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
    enableAcceleratedNetworking: supportsAcceleratedNetworking  // Key feature!
    enableIPForwarding: false
  }
}]

// Windows Virtual Machines
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
        patchSettings: {
          patchMode: 'AutomaticByOS'
          assessmentMode: 'ImageDefault'
        }
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: windowsOSVersion
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        diskSizeGB: osDiskSizeGB
        managedDisk: {
          storageAccountType: storageAccountType
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
      securityType: 'Standard'
    }
  }
  tags: {
    'azd-env-name': resourcePrefix
    purpose: 'accelerated-networking'
    vmSize: vmSize
    windowsVersion: windowsOSVersion
    acceleratedNetworking: string(supportsAcceleratedNetworking)
  }
}]

// PowerShell extension for network optimization
resource networkOptimizationExtension 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = [for i in range(0, vmCount): {
  parent: virtualMachine[i]
  name: 'OptimizeNetworking'
  location: location
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'CustomScriptExtension'
    typeHandlerVersion: '1.10'
    autoUpgradeMinorVersion: true
    settings: {
      fileUris: []
      commandToExecute: 'powershell.exe -ExecutionPolicy Unrestricted -Command "Write-Host \'Optimizing network settings...\'; Set-NetAdapterAdvancedProperty -DisplayName \'Receive Side Scaling\' -DisplayValue \'Enabled\' -ErrorAction SilentlyContinue; Set-NetAdapterAdvancedProperty -DisplayName \'TCP Checksum Offload (IPv4)\' -DisplayValue \'Enabled\' -ErrorAction SilentlyContinue; Set-NetAdapterAdvancedProperty -DisplayName \'TCP Checksum Offload (IPv6)\' -DisplayValue \'Enabled\' -ErrorAction SilentlyContinue; Set-NetAdapterAdvancedProperty -DisplayName \'UDP Checksum Offload (IPv4)\' -DisplayValue \'Enabled\' -ErrorAction SilentlyContinue; Set-NetAdapterAdvancedProperty -DisplayName \'UDP Checksum Offload (IPv6)\' -DisplayValue \'Enabled\' -ErrorAction SilentlyContinue; Write-Host \'Network optimization completed.\'"'
    }
  }
}]

// Performance monitoring extension
resource performanceExtension 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = [for i in range(0, vmCount): {
  parent: virtualMachine[i]
  name: 'AzurePerformanceDiagnostics'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.Performance.Diagnostics'
    type: 'AzurePerformanceDiagnosticsWindows'
    typeHandlerVersion: '1.0'
    autoUpgradeMinorVersion: true
    settings: {
      performanceScenario: 'basic'
      traceDurationInSeconds: 300
      perfCounterTrace: 'p'
      networkTrace: 'n'
      xperfTrace: 'x'
      storIOTrace: 's'
      srNumber: ''
      requestTimeUtc: ''
      resourceId: virtualMachine[i].id
    }
  }
  dependsOn: [
    networkOptimizationExtension[i]
  ]
}]

// Outputs
output vmNames array = [for i in range(0, vmCount): virtualMachine[i].name]
output publicIpAddresses array = [for i in range(0, vmCount): publicIpAddress[i].properties.ipAddress]
output fqdns array = [for i in range(0, vmCount): publicIpAddress[i].properties.dnsSettings.fqdn]
output rdpConnections array = [for i in range(0, vmCount): 'mstsc /v:${publicIpAddress[i].properties.ipAddress}']

output networkConfiguration object = {
  acceleratedNetworkingEnabled: supportsAcceleratedNetworking
  vmSize: vmSize
  vmSizeSupportsAcceleratedNetworking: supportsAcceleratedNetworking
  networkOptimizations: [
    'Receive Side Scaling'
    'TCP/UDP Checksum Offload'
    'Performance Diagnostics'
  ]
}

output deploymentSummary object = {
  resourceGroup: resourceGroup().name
  location: location
  vmSize: vmSize
  vmCount: vmCount
  windowsVersion: windowsOSVersion
  vnetName: vnetName
  acceleratedNetworking: supportsAcceleratedNetworking
  premiumStorage: enablePremiumStorage
  extensions: [
    'Network Optimization'
    'Performance Diagnostics'
  ]
}
