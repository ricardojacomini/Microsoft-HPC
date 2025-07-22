# 🎯 AMLFS Deployment Quick Reference Card
**Generated:** July 21, 2025  
**Status:** ✅ DEPLOYED SUCCESSFULLY

## 📊 Your Deployment Details

| Resource | Name/Value |
|----------|------------|
| **Resource Group** | `aml-rsj-managed-identity-20250721-1521` |
| **AMLFS Name** | `amlfs-prod-20250721-152206` |
| **Storage Account** | `storagez7xghrwomjhiw` |
| **Managed Identity** | `amlfs-identity-z7xghrwomjhiw` |
| **VNet** | `vnet` |
| **Location** | `East US` |
| **Zone** | `2` |

## 🔧 Essential Commands

### Check Deployment Status
```powershell
az resource list --resource-group "aml-rsj-managed-identity-20250721-1521" --query "[].{Name:name,Type:type,State:properties.provisioningState}" -o table
```

### Get Mount Address
```powershell
az resource show --resource-group "aml-rsj-managed-identity-20250721-1521" --name "amlfs-prod-20250721-152206" --resource-type "Microsoft.StorageCache/amlFileSystems" --query "properties.mountAddress" -o tsv
```

### Configure HSM
```powershell
$resourceGroup = "aml-rsj-managed-identity-20250721-1521"
$amlfsName = "amlfs-prod-20250721-152206"
$storageAccount = "storagez7xghrwomjhiw"
$containerUrl = "https://$storageAccount.blob.core.windows.net/amlfs-data"
$hsmSettings = '[{"importPrefix":"/","exportPrefix":"/export","container":"' + $containerUrl + '"}]'
$amlfsId = "/subscriptions/7bfe6334-68ac-4597-9cd4-59c9ab82e3e0/resourceGroups/$resourceGroup/providers/Microsoft.StorageCache/amlFileSystems/$amlfsName"
az resource update --ids $amlfsId --set "properties.hsm.settings=$hsmSettings"
```

## 🖥️ Linux Client Setup

### Install Lustre Client (Ubuntu)
```bash
sudo apt-get update
sudo apt-get install lustre-client-modules-$(uname -r)
```

### Mount AMLFS
```bash
sudo mkdir -p /mnt/amlfs
sudo mount -t lustre <MOUNT_ADDRESS>/lustrefs /mnt/amlfs
```

### Verify Mount
```bash
df -h /mnt/amlfs
lfs df /mnt/amlfs
```

## 🧪 Performance Testing

### Basic I/O Test
```bash
# Write test
dd if=/dev/zero of=/mnt/amlfs/test-1GB bs=1M count=1024

# Read test
dd if=/mnt/amlfs/test-1GB of=/dev/null bs=1M
```

### HSM Test
```bash
# Create test file
echo "HSM test data" > /mnt/amlfs/hsm-test.txt

# Archive to cold storage
lfs hsm_archive /mnt/amlfs/hsm-test.txt

# Check HSM status
lfs hsm_state /mnt/amlfs/hsm-test.txt
```

## 📞 Support Resources

- **Documentation**: `README-managed-identity.md`
- **Next Steps Script**: `next-steps.ps1`
- **Mount Info**: `amlfs-mount-info.txt`
- **Azure Docs**: [Azure Managed Lustre](https://docs.microsoft.com/azure/hpc-cache/managed-lustre)

---
**🎉 Your production-ready AMLFS with managed identity is deployed and ready for use!**
