# ✅ AMLFS Complete Setup Checklist

This checklist provides a step-by-step guide for deploying and configuring Azure Managed Lustre File System (AMLFS) with managed identity.

## 🚀 Pre-Deployment Steps
- [ ] **Azure CLI Login**: `az login`
- [ ] **Choose Deployment Version**: Basic (`README.md`) or Managed Identity (`README-managed-identity.md`)
- [ ] **Check AMLFS Quota**: Run quota check commands from README
- [ ] **Verify Resource Group**: Create or select target resource group

## 🏗️ Infrastructure Deployment
- [ ] **Test Zone Availability**: 
  ```powershell
  # Basic version
  .\scripts\Test-AMLFSZones.ps1 -ResourceGroup "aml-rsj" -Location "eastus"
  
  # OR Managed Identity version (recommended)
  $rg = "amlfs-managed-identity-$(Get-Date -Format 'yyyyMMdd-HHmm')"
  .\scripts\Test-AMLFSZones-ManagedIdentity.ps1 -ResourceGroup $rg -Location "eastus"
  ```
- [ ] **Verify Deployment**: Check Azure portal for successful AMLFS deployment
- [ ] **Note Resource Names**: Record AMLFS name, storage account, managed identity names

## 🤖 Automated Post-Deployment (Managed Identity Only)
- [ ] **Run Automation Script**: 
  ```powershell
  .\scripts\next-steps.ps1 -ResourceGroup $rg -AmlfsName "amlfs-prod-xxx" -StorageAccount "storagexxxxx"
  ```
- [ ] **Verify Script Output**: 
  - [ ] HSM configuration applied
  - [ ] VM creation completed (or instructions provided)
  - [ ] Linux scripts generated

## � Manual Client Setup Steps

### Step 1: Create Ubuntu VM (if not done by automation)
- [ ] **Create VM in Same VNet**:
  ```powershell
  az vm create \
    --resource-group $rg \
    --name "amlfs-ubuntu-client" \
    --image "Ubuntu2404" \
    --size "Standard_D4s_v3" \
    --vnet-name "vnet" \
    --subnet "amlfs" \
    --generate-ssh-keys
  ```
- [ ] **Note VM Public IP**: Record for SSH access
- [ ] **Test SSH Connection**: `ssh azureuser@<VM_PUBLIC_IP>`

### Step 2: Upload Scripts to VM
- [ ] **Upload Lustre Installation Scripts**:
  ```bash
  scp scripts/kernel-downgrade.sh azureuser@<VM_IP>:~/
  scp scripts/kernel-downgrade-part2.sh azureuser@<VM_IP>:~/ # (if generated)
  scp scripts/mount-amlfs.sh azureuser@<VM_IP>:~/ # (if generated)
  ```

### Step 3: Install Lustre Client (Two-Part Process)
- [ ] **SSH to VM**: `ssh azureuser@<VM_IP>`
- [ ] **Make Scripts Executable**:
  ```bash
  chmod +x kernel-downgrade.sh
  chmod +x kernel-downgrade-part2.sh  # (if available)
  chmod +x mount-amlfs.sh  # (if available)
  ```
- [ ] **Part 1 - Kernel Setup** (requires reboot):
  ```bash
  sudo ./kernel-downgrade.sh
  # System will reboot automatically
  ```
- [ ] **Wait for Reboot**: VM will restart with compatible kernel
- [ ] **SSH Back to VM**: Reconnect after reboot
- [ ] **Part 2 - Lustre Installation**:
  ```bash
  sudo ./kernel-downgrade-part2.sh
  ```
- [ ] **Verify Installation**:
  ```bash
  which lfs
  lfs --version
  lsmod | grep lustre
  ```

### Step 4: Mount AMLFS Filesystem
- [ ] **Use Generated Mount Script** (if available):
  ```bash
  ./mount-amlfs.sh
  ```
- [ ] **OR Manual Mount**:
  ```bash
  # Create mount point
  sudo mkdir -p /amlfs-prod-xxx
  
  # Mount with optimized options (replace with your AMLFS IP)
  sudo mount -t lustre -o noatime,user_xattr,flock <MOUNT_ADDRESS>@tcp0:/lustrefs /amlfs-prod-xxx
  ```
- [ ] **Verify Mount**:
  ```bash
  df -h /amlfs-prod-xxx
  ls -la /amlfs-prod-xxx
  ```

## 🧪 Testing & Validation

### Step 5: Basic Functionality Tests
- [ ] **Test Write Access**:
  ```bash
  echo "Hello AMLFS!" > /amlfs-prod-xxx/test.txt
  cat /amlfs-prod-xxx/test.txt
  ```
- [ ] **Test Performance** (optional):
  ```bash
  # Write test
  dd if=/dev/zero of=/amlfs-prod-xxx/perf-test bs=1M count=100
  
  # Read test  
  dd if=/amlfs-prod-xxx/perf-test of=/dev/null bs=1M
  
  # Cleanup
  rm /amlfs-prod-xxx/perf-test
  ```

### Step 6: HSM Testing (Managed Identity Only)
- [ ] **Test HSM Archive**:
  ```bash
  echo "HSM test data" > /amlfs-prod-xxx/hsm-test.txt
  lfs hsm_archive /amlfs-prod-xxx/hsm-test.txt
  ```
- [ ] **Check HSM Status**:
  ```bash
  lfs hsm_state /amlfs-prod-xxx/hsm-test.txt
  ```
- [ ] **Test HSM Restore**:
  ```bash
  lfs hsm_restore /amlfs-prod-xxx/hsm-test.txt
  cat /amlfs-prod-xxx/hsm-test.txt
  ```

## 🎯 Production Setup (Optional)

### Step 7: Auto-Mount Configuration
- [ ] **Add to /etc/fstab** for persistent mounting:
  ```bash
  echo "<MOUNT_ADDRESS>@tcp0:/lustrefs /amlfs-prod-xxx lustre noatime,user_xattr,flock,_netdev 0 0" | sudo tee -a /etc/fstab
  ```
- [ ] **Test Auto-Mount**:
  ```bash
  sudo umount /amlfs-prod-xxx
  sudo mount -a
  df -h /amlfs-prod-xxx
  ```

### Step 8: Monitoring Setup
- [ ] **Check Lustre Health**:
  ```bash
  lfs df /amlfs-prod-xxx
  lfs check servers
  ```
- [ ] **Monitor Azure Resources**:
  ```powershell
  az resource list --resource-group $rg --query "[].{Name:name,State:properties.provisioningState}" -o table
  ```

## 📚 Reference Documentation

- [ ] **📖 [Main README](README.md)** - Choose deployment version
- [ ] **📖 [Basic Guide](README-basic.md)** - Basic AMLFS deployment  
- [ ] **📖 [Managed Identity Guide](README-managed-identity.md)** - Production deployment
- [ ] **📖 [Scripts Documentation](scripts/README.md)** - Automation scripts
- [ ] **📖 [Templates Documentation](templates/README.md)** - Bicep templates

## 🆘 Troubleshooting Checklist

- [ ] **VM Creation Issues**: Try different VM sizes or zones using `scripts/create-vm.ps1`
- [ ] **Kernel Installation Issues**: Check internet connectivity and repository setup
- [ ] **Mount Issues**: Verify network connectivity with AMLFS IP
- [ ] **HSM Issues**: Ensure managed identity has proper permissions
- [ ] **Performance Issues**: Check Lustre client modules and mount options

## ✅ Success Indicators

Your AMLFS setup is successful when:
- [ ] ✅ AMLFS deployed and healthy in Azure Portal
- [ ] ✅ Ubuntu VM created and accessible via SSH  
- [ ] ✅ Lustre client installed (compatible kernel + modules)
- [ ] ✅ AMLFS filesystem mounted and accessible
- [ ] ✅ Can read/write files to AMLFS
- [ ] ✅ HSM archival working (managed identity version)
- [ ] ✅ Performance tests pass
- [ ] ✅ Auto-mount configured (optional)

---

**📝 Note**: For managed identity deployments, run `.\scripts\next-steps.ps1` first to automate Steps 1-2, then follow the manual steps above.
