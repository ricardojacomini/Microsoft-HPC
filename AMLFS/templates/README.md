# AMLFS Infrastructure Templates

This directory contains Bicep templates for deploying Azure ML File Systems (AMLFS) with different configurations.

## 📁 Template Files

### 🟦 **Basic Version Templates**
| File | Purpose | Usage |
|------|---------|-------|
| `infra-basic.bicep` | Minimal AMLFS deployment | Development & testing scenarios |

### 🟩 **Managed Identity Version Templates**
| File | Purpose | Usage |
|------|---------|-------|
| `infra-managed-identity.bicep` | Full-featured AMLFS with managed identity | Production deployments |
| `infra-managed-identity.json` | Parameters file for managed identity template | Configuration values |

### 🔧 **Legacy Templates**
| File | Purpose | Status |
|------|---------|--------|
| `infra.bicep` | Original template | Legacy - use specific versions above |

## 🚀 **Quick Deployment Examples**

### Basic Version:
```powershell
# From repository root
az deployment group create \
  --resource-group "aml-rsj" \
  --template-file "templates/infra-basic.bicep" \
  --parameters "availabilityZone=2" \
  --name "deploy-basic-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
```

### Managed Identity Version:
```powershell
# From repository root
az deployment group create \
  --resource-group "aml-rsj-managed-identity" \
  --template-file "templates/infra-managed-identity.bicep" \
  --parameters "availabilityZone=2" \
  --name "deploy-managed-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
```

### With Parameters File:
```powershell
# Using parameters file
az deployment group create \
  --resource-group "aml-rsj-managed-identity" \
  --template-file "templates/infra-managed-identity.bicep" \
  --parameters "@templates/infra-managed-identity.json" \
  --name "deploy-with-params-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
```

## 📋 **Template Parameters**

### Basic Template Parameters:
| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `fsname` | string | `'amlfs'` | AMLFS resource name |
| `location` | string | `resourceGroup().location` | Azure region |
| `availabilityZone` | int | `2` | Availability zone (1, 2, or 3) |
| `vnet_name` | string | `'vnet'` | Virtual network name |
| `vnet_cidr` | string | `'10.242.0.0/23'` | VNet CIDR block |

### Managed Identity Template Parameters:
| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `fsname` | string | `'amlfs'` | AMLFS resource name |
| `location` | string | `resourceGroup().location` | Azure region |
| `availabilityZone` | int | `2` | Availability zone (1, 2, or 3) |
| `vnet_name` | string | `'vnet'` | Virtual network name |
| `vnet_cidr` | string | `'10.242.0.0/23'` | VNet CIDR block |
| `storage_name` | string | `'storage{uniqueString}'` | Storage account name |
| `managedIdentityName` | string | `'amlfs-identity-{uniqueString}'` | Managed identity name |

## 🔍 **Template Validation**

Before deploying, validate your templates:

```powershell
# Validate basic template
az deployment group validate \
  --resource-group "aml-rsj" \
  --template-file "templates/infra-basic.bicep" \
  --parameters "availabilityZone=2"

# Validate managed identity template  
az deployment group validate \
  --resource-group "aml-rsj-managed-identity" \
  --template-file "templates/infra-managed-identity.bicep" \
  --parameters "availabilityZone=2"
```

## 🏗️ **Template Architecture**

### Basic Template Creates:
- ✅ Azure Managed Lustre File System (AMLFS)
- ✅ Virtual Network with dedicated subnet
- ✅ Network Security Group with basic rules
- ✅ 8TiB Premium-250 storage

### Managed Identity Template Creates:
- ✅ Everything from Basic template, plus:
- ✅ User-Assigned Managed Identity
- ✅ Storage Account with private container
- ✅ Automatic RBAC role assignments
- ✅ Enhanced security rules (Lustre ports)
- ✅ HSM (Hierarchical Storage Management) support

## 📖 **Documentation References**

- **Main README**: `../README.md` - Choose your deployment version
- **Basic Guide**: `../README-basic.md` - Complete basic deployment documentation
- **Managed Identity Guide**: `../README-managed-identity.md` - Production deployment documentation
- **Scripts**: `../scripts/README.md` - Automation scripts documentation

## 🆘 **Troubleshooting Templates**

### Common Issues:
- **BCP081 Warnings**: Expected for AMLFS preview APIs - safe to ignore
- **Zone Availability**: Use zone testing scripts before deployment
- **Capacity Issues**: Try different availability zones (1, 2, 3)
- **RBAC Permissions**: Ensure User Access Administrator role for managed identity template

### Template Compilation:
```powershell
# Check template syntax
az bicep build --file "templates/infra-basic.bicep"
az bicep build --file "templates/infra-managed-identity.bicep"
```

---

**💡 These templates are production-tested and ready for deployment!**
