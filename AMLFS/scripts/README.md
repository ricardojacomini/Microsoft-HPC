# AMLFS Scripts Directory

This directory contains automation scripts for AMLFS deployment and management.

## 📁 Script Categories

### 🚀 **Deployment & Testing Scripts**
| Script | Purpose | Usage |
|--------|---------|-------|
| `Test-AMLFSZones.ps1` | Basic version zone testing and deployment | `.\Test-AMLFSZones.ps1 -ResourceGroup "aml-rsj" -Location "eastus"` |
| `Test-AMLFSZones-ManagedIdentity.ps1` | Managed identity version zone testing and deployment | `.\Test-AMLFSZones-ManagedIdentity.ps1 -ResourceGroup "amlfs-mi" -Location "eastus"` |

### 🔧 **Post-Deployment Automation**
| Script | Purpose | Usage |
|--------|---------|-------|
| `next-steps.ps1` | Automate HSM config, VM creation, and script generation | `.\next-steps.ps1 -ResourceGroup "aml-rsj" -AmlfsName "amlfs-prod"` |
| `create-vm.ps1` | VM creation with multiple size fallbacks | `.\create-vm.ps1 -ResourceGroup "aml-rsj"` |
| `Check-ManagedIdentityPermissions.ps1` | Validate managed identity RBAC permissions | `.\Check-ManagedIdentityPermissions.ps1 -ResourceGroupName "aml-rsj" -ManagedIdentityName "identity"` |

### 🐧 **Linux Client Setup Scripts**
| Script | Purpose | Usage |
|--------|---------|-------|
| `kernel-downgrade.sh` | Ubuntu kernel setup for Lustre (Part 1) | `sudo ./kernel-downgrade.sh` |
| `kernel-downgrade-part2.sh` | Lustre client installation (Part 2, after reboot) | `sudo ./kernel-downgrade-part2.sh` |
| `mount-amlfs.sh` | Mount AMLFS with optimized options | `./mount-amlfs.sh` |

### 🔍 **Diagnostic & Testing Scripts**
| Script | Purpose | Usage |
|--------|---------|-------|
| `network-test.sh` | Network connectivity testing | `./network-test.sh` |
| `test-mount.sh` | AMLFS mount testing | `./test-mount.sh` |
| `direct-connection-test.sh` | Direct AMLFS connection testing | `./direct-connection-test.sh` |
| `full-diagnostic.sh` | Complete diagnostic check | `./full-diagnostic.sh` |

### 🛠️ **Utility Scripts**
| Script | Purpose | Usage |
|--------|---------|-------|
| `fix-ssh.ps1` | SSH configuration fixes | `.\fix-ssh.ps1` |
| `ssh-commands.sh` | SSH command utilities | `./ssh-commands.sh` |

## 📋 **Script Workflow**

### Basic Deployment:
```
1. Test-AMLFSZones.ps1           # Deploy basic AMLFS
2. (Manual VM creation)          # Create Linux client
3. kernel-downgrade.sh           # Install Lustre client
4. mount-amlfs.sh               # Mount filesystem
```

### Managed Identity Deployment:
```
1. Test-AMLFSZones-ManagedIdentity.ps1  # Deploy AMLFS with managed identity
2. next-steps.ps1                       # Automate HSM, VM, and scripts
   ├── HSM configuration
   ├── VM creation (create-vm.ps1)
   └── Generate Linux scripts
3. kernel-downgrade.sh                  # Install Lustre client (Part 1)
4. kernel-downgrade-part2.sh           # Install Lustre client (Part 2)
5. mount-amlfs.sh                      # Mount filesystem
```

## 🎯 **Quick Start Examples**

### Deploy Basic AMLFS:
```powershell
cd scripts
.\Test-AMLFSZones.ps1 -ResourceGroup "aml-rsj" -Location "eastus"
```

### Deploy Managed Identity AMLFS with Full Automation:
```powershell
cd scripts
$rg = "amlfs-managed-identity-$(Get-Date -Format 'yyyyMMdd-HHmm')"
.\Test-AMLFSZones-ManagedIdentity.ps1 -ResourceGroup $rg -Location "eastus"
.\next-steps.ps1 -ResourceGroup $rg -AmlfsName "amlfs-prod" -StorageAccount "storage123"
```

### Setup Lustre Client on Ubuntu:
```bash
# Upload scripts to VM
scp scripts/kernel-downgrade.sh azureuser@<VM_IP>:~/

# On the VM:
chmod +x kernel-downgrade.sh
sudo ./kernel-downgrade.sh
# System reboots automatically

# After reboot:
chmod +x kernel-downgrade-part2.sh  
sudo ./kernel-downgrade-part2.sh

# Mount filesystem:
chmod +x mount-amlfs.sh
./mount-amlfs.sh
```

## 📖 **Documentation References**

- **Main README**: `../README.md` - Choose between Basic and Managed Identity versions
- **Basic Version**: `../README-basic.md` - Complete basic deployment guide  
- **Managed Identity**: `../README-managed-identity.md` - Production deployment guide

## 🆘 **Troubleshooting**

- **Script Execution Policy**: `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser`
- **Azure CLI**: Ensure `az login` is completed and proper permissions
- **Linux Scripts**: Ensure execute permissions: `chmod +x script-name.sh`
- **Path Issues**: Run scripts from the `scripts/` directory or use relative paths

---

**💡 All scripts are designed to work together as a complete AMLFS deployment and management toolkit!**
