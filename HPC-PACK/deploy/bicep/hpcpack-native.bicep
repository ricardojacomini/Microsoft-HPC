@description('Prefix for Key Vault name')
param vaultNamePrefix string = 'hpcpack-kv'

@description('Azure location for resources')
param location string = resourceGroup().location

@description('Certificate name in Key Vault')
param certName string = 'hpcCert'

@description('Common Name for certificate subject')
param commonName string = 'HPC Pack Node Communication'

@description('HPC Pack cluster name')
param clusterName string = 'hpcpack-cluster'

@description('Head node VM size')
param headNodeSize string = 'Standard_D4s_v5'

@description('Compute node VM size')
param computeNodeSize string = 'Standard_D4s_v5'

@description('Number of compute nodes')
param computeNodeCount int = 2

@description('Admin username for cluster nodes')
param adminUsername string = 'hpcadmin'

@secure()
@description('Admin password for cluster nodes')
param adminPassword string

@description('Optional ObjectId for Certificates Officer role. If empty, fallback to managed identity.')
param certOfficerPrincipalId string = ''

// Generate Key Vault name
var suffix = uniqueString(resourceGroup().id)
var vaultName = toLower(take('${vaultNamePrefix}-${suffix}', 24))

// Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2024-04-01-preview' = {
  name: vaultName
  location: location
  properties: {
    sku: { name: 'standard', family: 'A' }
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


resource assignKeyVaultCertificatesOfficer 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, vaultName, certOfficerPrincipalId, 'a4417e6f-fecd-4de8-b567-7b0420556985')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'a4417e6f-fecd-4de8-b567-7b0420556985') // Key Vault Certificates Officer
    // If caller supplied certOfficerPrincipalId use it; otherwise fall back to the managed identity created below
    principalId: length(certOfficerPrincipalId) > 0 ? certOfficerPrincipalId : userMiForNewCert.properties.principalId
    // principalType can be omitted so Azure infers it
  }
  dependsOn: [
    keyVault
    userMiForNewCert
  ]
}


// // Create certificate directly in Key Vault
// resource keyVaultCert 'Microsoft.KeyVault/vaults/certificates@2023-07-01' = {
//   parent: keyVault
//   name: certName
//   properties: {
//     certificatePolicy: {
//       issuerParameters: {
//         name: 'Self'
//       }
//       keyProperties: {
//         exportable: true
//         keyType: 'RSA'
//         keySize: 2048
//         reuseKey: true
//       }
//       secretProperties: {
//         contentType: 'application/x-pkcs12'
//       }
//       x509CertificateProperties: {
//         subject: 'CN=${commonName}'
//         validityInMonths: 60
//         ekus: [
//           '1.3.6.1.5.5.7.3.1' // Server Authentication
//           '1.3.6.1.5.5.7.3.2' // Client Authentication
//         ]
//         keyUsage: [
//           'digitalSignature'
//           'keyEncipherment'
//           'keyCertSign'
//         ]
//       }
//     }
//     certificateAttributes: {
//       enabled: true
//     }
//     lifetimeActions: [
//       {
//         trigger: {
//           daysBeforeExpiry: 30
//         }
//         action: {
//           actionType: 'AutoRenew'
//         }
//       }
//     ]
//   }
//   dependsOn: [
//     keyVault
//     assignKeyVaultCertificatesOfficer
//   ]
// }

resource userMiForNewCert 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'userMiForNewCert'
  location: location
}

// Create certificate directly in Key Vault (native child resource) to avoid deploymentScript/storage-account fragility
resource keyVaultCert 'Microsoft.KeyVault/vaults/certificates@2023-07-01' = {
  parent: keyVault
  name: certName
  properties: {
    certificatePolicy: {
      issuerParameters: {
        name: 'Self'
      }
      keyProperties: {
        exportable: true
        keyType: 'RSA'
        keySize: 2048
        reuseKey: true
      }
      secretProperties: {
        contentType: 'application/x-pkcs12'
      }
      x509CertificateProperties: {
        subject: 'CN=${commonName}'
        validityInMonths: 60
        ekus: [
          '1.3.6.1.5.5.7.3.1'
          '1.3.6.1.5.5.7.3.2'
        ]
        keyUsage: [
          'digitalSignature'
          'keyEncipherment'
          'keyAgreement'
        ]
      }
    }
    certificateAttributes: {
      enabled: true
    }
    lifetimeActions: [
      {
        trigger: {
          daysBeforeExpiry: 30
        }
        action: {
          actionType: 'AutoRenew'
        }
      }
    ]
  }
  dependsOn: [ keyVault, assignKeyVaultCertificatesOfficer ]
}

// HPC Pack Cluster
resource hpcCluster 'Microsoft.HPC/cluster@2024-01-01' = {
  name: clusterName
  location: location
  properties: {
    headNode: {
      vmSize: headNodeSize
      adminUsername: adminUsername
      adminPassword: adminPassword
    }
    computeNodes: [
      {
        count: computeNodeCount
        vmSize: computeNodeSize
      }
    ]
    nodeCommunicationCertificate: {
      sourceVault: {
        id: keyVault.id
      }
      certificateUrl: keyVaultCert.properties.secretId
    }
  }
  dependsOn: [ keyVaultCert ]
}

// Outputs
output clusterInfo object = {
  clusterName: clusterName
  certificateUrl: keyVaultCert.properties.secretId
  vaultName: vaultName
}
