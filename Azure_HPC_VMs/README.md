# H Series VM with InfiniBand Deployment - Usage Examples

## Overview
The `deploy_h_series_ib_win2019_enhanced.ps1` script creates Azure H series VMs with InfiniBand/RDMA support on Windows Server 2019 without HPC Pack dependencies. The enhanced version includes cost optimization features, quota checking, and pricing comparisons.

**Available Scripts:**
- `deploy_h_series_ib_win2019_enhanced.ps1` - Enhanced version with HCS Family support, quota checking, and cost optimization
- `deploy_h_series_ib_win2019.ps1` - Original version (basic H Family VMs only)

**✅ Recommended**: Use the enhanced version for better quota support and cost optimization.

## Prerequisites
1. Azure PowerShell module installed: `Install-Module -Name Az`
2. Azure account with appropriate permissions
3. Connected to Azure: `Connect-AzAccount`

## Basic Usage

### 1. Show pricing comparison (information only)
```powershell
.\deploy_h_series_ib_win2019_enhanced.ps1 -ShowPricing
```

### 2. Check quota requirements (information only)
```powershell
.\deploy_h_series_ib_win2019_enhanced.ps1 -CheckQuota
```

### 3. Show pricing and check quota (information only)
```powershell
.\deploy_h_series_ib_win2019_enhanced.ps1 -ShowPricing -CheckQuota
```

### 4. Use cost-effective option with deployment
```powershell
.\deploy_h_series_ib_win2019_enhanced.ps1 -VmCount 2
```

### 5. Use budget HCS Family option (✅ Available with your quota)
```powershell
.\deploy_h_series_ib_win2019_enhanced.ps1 -VmSize "Standard_HC44-16rs" -VmCount 1 -CheckQuota
```

### 6. Use balanced HCS Family option (✅ Available with your quota)
```powershell
.\deploy_h_series_ib_win2019_enhanced.ps1 -VmSize "Standard_HC44-32rs" -VmCount 2 -CheckQuota
```

### 7. Use traditional H Family option (⚠️ Requires quota increase)
```powershell
.\deploy_h_series_ib_win2019_enhanced.ps1 -VmSize "Standard_HB120-16rs_v3" -VmCount 1 -CheckQuota
```

### 8. Try different region if quota insufficient
```powershell
.\deploy_h_series_ib_win2019_enhanced.ps1 -VmSize "Standard_HB120-16rs_v3" -VmCount 1 -Location "westus2" -CheckQuota
```

### 7. Dry run with pricing
```powershell
.\deploy_h_series_ib_win2019_enhanced.ps1 -ShowPricing -WhatIf
```

### 8. Default Deployment (2 VMs)
```powershell
.\deploy_h_series_ib_win2019_enhanced.ps1
```

### 9. Custom Configuration
```powershell
.\deploy_h_series_ib_win2019_enhanced.ps1 -ResourceGroupName "MyHPC-RG" -Location "westus2" -VmCount 4 -VmPrefix "HPC-Node"
```

### 10. Different VM Size
```powershell
.\deploy_h_series_ib_win2019_enhanced.ps1 -VmSize "Standard_HB60rs" -VmCount 3
```

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-ResourceGroupName` | `HSeries-IB-jacomini` | Name of the resource group to create/use |
| `-Location` | `eastus` | Azure region for deployment |
| `-VmSize` | `Standard_HC44rs` | Azure VM size (H series recommended, cost-effective default) |
| `-VmCount` | `2` | Number of VMs to deploy |
| `-VmPrefix` | `HSeries-IB` | Prefix for VM names (VMs will be named Prefix1, Prefix2, etc.) |
| `-AdminUsername` | `azureuser` | Administrator username for all VMs |
| `-WhatIf` | `false` | Preview deployment without creating resources (dry run) |
| `-CheckQuota` | `false` | Check Azure quota availability before deployment (information-only when used alone) |
| `-ShowPricing` | `false` | Display pricing comparison for all available VM sizes (information-only when used alone) |

## Supported H Series VM Sizes

The enhanced script supports the following H series VM sizes with InfiniBand and includes cost optimization:

**HCS Family (✅ Available with your 1320 vCPU quota):**
- `Standard_HC44-16rs` (16 cores, 352 GB RAM, ~$0.80/hour) - **Budget HCS option**
- `Standard_HC44-32rs` (32 cores, 352 GB RAM, ~$1.60/hour) - **Balanced HCS option**

**H Family (⚠️ Requires quota increase - only 8 vCPUs available):**
- `Standard_HC44rs` (44 cores, 352 GB RAM, ~$2.20/hour) - **Recommended for cost-effectiveness**
- `Standard_HB120-16rs_v3` (16 cores, 456 GB RAM, ~$0.95/hour) - **Budget option**
- `Standard_HB120-32rs_v3` (32 cores, 456 GB RAM, ~$1.90/hour) - **Balanced performance**
- `Standard_HB120-64rs_v3` (64 cores, 456 GB RAM, ~$3.80/hour) - **High performance**
- `Standard_HB120rs_v3` (120 cores, 456 GB RAM, ~$7.20/hour) - **Full HB series**
- `Standard_HB176rs_v4` (176 cores, 768 GB RAM, ~$12.00/hour) - **Latest generation**

Use `-ShowPricing` parameter to see detailed cost comparison and choose the right VM size for your workload.

## Information-Only Mode

The enhanced script supports **information-only mode** when using `-ShowPricing` or `-CheckQuota` flags alone:

- **No Azure authentication required** for pricing information
- **No deployment initiated** - exits after displaying information
- **Quick cost comparison** without needing Azure credentials
- **Quota checking** shows requirements and current usage (if Azure CLI is authenticated)

**Examples:**
- `.\deploy_h_series_ib_win2019_enhanced.ps1 -ShowPricing` - Shows all VM pricing without authentication
- `.\deploy_h_series_ib_win2019_enhanced.ps1 -CheckQuota` - Shows quota requirements and current usage
- `.\deploy_h_series_ib_win2019_enhanced.ps1 -ShowPricing -CheckQuota` - Shows both pricing and quota information

To actually deploy VMs, combine with other parameters or run without information-only flags.

## What the Script Does

1. **Sets up Azure infrastructure:**
   - Creates resource group
   - Creates virtual network with InfiniBand-optimized subnet
   - Configures network security group with RDMA/InfiniBand rules

2. **Deploys H Series VMs:**
   - Creates VMs with Windows Server 2019
   - Enables accelerated networking (required for InfiniBand)
   - Configures Trusted Launch with disabled features for InfiniBand compatibility

3. **Installs InfiniBand drivers:**
   - Downloads latest Mellanox WinOF-2 drivers
   - Installs drivers silently
   - Verifies installation and RDMA capabilities

4. **Tests connectivity:**
   - Verifies InfiniBand adapters are recognized
   - Tests basic network connectivity between VMs
   - Checks RDMA capabilities

## Post-Deployment Verification

After deployment, connect to the VMs and run these commands to verify InfiniBand:

```powershell
# Check RDMA adapters
Get-NetAdapterRdma

# Check SMB network interfaces (should show RDMA capable)
Get-SmbClientNetworkInterface

# Check network adapters
Get-NetAdapter | Where-Object { $_.Name -like '*Ethernet*' }

# Detailed adapter information (usually "Ethernet 2" for InfiniBand)
Get-NetAdapter | Where-Object { $_.Name -eq "Ethernet 2" } | Format-List *
```

## **🎯 Verified InfiniBand Results (August 6, 2025)**

**Successfully deployed H-series VM results:**

### **Network Adapters Found:**
| Name | Interface Description | Link Speed | Status |
|------|----------------------|------------|--------|
| Ethernet | Microsoft Hyper-V Network Adapter | 50 Gbps | Up |
| **Ethernet 2** | **Mellanox ConnectX-5 Virtual Adapter** | **100 Gbps** | **Up** ✅ |
| **Ethernet 4** | **Mellanox ConnectX-4 Lx Virtual Ethernet Adapter #2** | **50 Gbps** | **Up** ✅ |

### **RDMA Status:**
| Name | RDMA Enabled | Status |
|------|-------------|---------|
| Ethernet | False | Standard network |
| **Ethernet 2** | **True** ✅ | **Primary InfiniBand** |
| **Ethernet 4** | **True** ✅ | **Secondary InfiniBand** |

### **SMB Client Network Interfaces:**
| Interface Index | RDMA Capable | Link Speed |
|----------------|-------------|------------|
| **4** | **True** ✅ | **100 Gbps** |
| 7 | False | 50 Gbps |

**✅ Result**: **Two functional InfiniBand adapters** with RDMA enabled, ready for HPC workloads!

## Troubleshooting

### Quota Issues:

**BREAKTHROUGH**: HCS Family Quota Discovered!

**Great News**: You have **Standard HCS Family vCPUs** quota with **1320 vCPUs available** in East US! This opens up new VM options:

**HCS Family VMs (Available with your quota):**
- `Standard_HC44-16rs` (16 vCPUs, 352 GB RAM, ~$0.80/hour) - **Budget HCS option** ✅
- `Standard_HC44-32rs` (32 vCPUs, 352 GB RAM, ~$1.60/hour) - **Balanced HCS option** ✅  
- `Standard_HC44rs` (44 vCPUs, 352 GB RAM, ~$2.20/hour) - **Full HC performance** ⚠️ (uses different quota)

**Problem**: "Insufficient quota! Need X vCPUs but only 8 available"

**Root Cause**: The script was checking the wrong quota family. H-series VMs have different quota families:
- **Standard H Family vCPUs**: 8 vCPUs available (for Standard_HC44rs, Standard_HB120-* series)
- **Standard HCS Family vCPUs**: 1320 vCPUs available (for Standard_HC44-16rs, Standard_HC44-32rs) ✅

**Solutions**:
1. **Use HCS Family VMs** (Recommended - Available Now!):
   ```powershell
   # Use budget HCS option (16 vCPUs, plenty of quota available)
   .\deploy_h_series_ib_win2019_enhanced.ps1 -VmSize "Standard_HC44-16rs" -VmCount 1
   
   # Use balanced HCS option (32 vCPUs, still within quota)
   .\deploy_h_series_ib_win2019_enhanced.ps1 -VmSize "Standard_HC44-32rs" -VmCount 1
   
   # You can even deploy multiple VMs with your 1320 vCPU quota!
   .\deploy_h_series_ib_win2019_enhanced.ps1 -VmSize "Standard_HC44-16rs" -VmCount 4  # Uses 64 vCPUs
   ```

2. **Register Required Azure Feature** (One-time setup):
   ```powershell
   # Register the required feature for HCS Family VMs
   az feature register --namespace Microsoft.Compute --name UseStandardSecurityType
   az provider register -n Microsoft.Compute
   
   # Wait 5-10 minutes for propagation, then try deployment
   # If you get "feature not available" error, wait longer or try different region
   ```

   **Feature Registration Issue**: If you see this error:
   ```
   The value 'Standard' is not available for property 'securityType' until the feature 
   'Microsoft.Compute\UseStandardSecurityType' is registered
   ```
   
   **Solutions**:
   - **Wait 5-10 minutes** - Feature propagation takes time across Azure regions
   - **Try different region**: `.\deploy_h_series_ib_win2019_enhanced.ps1 -VmSize "Standard_HC44-16rs" -VmCount 1 -Location "westus2"`
   - **Use specific resource group**: `.\deploy_h_series_ib_win2019_enhanced.ps1 -VmSize "Standard_HC44-16rs" -VmCount 1 -ResourceGroupName "HSeries-IB-jacomini"`
   - **✅ WORKING SOLUTION**: Switch subscriptions if needed: `az account set --subscription "4ff8254c-98ae-4bda-b37f-b30d4b289a5b"`

## **✅ Verified Working Deployment Commands**

Based on successful deployment on August 6, 2025:

### **1. Change to HPC & AI Support Team Shared Subscription:**
```powershell
az account set --subscription "4ff8254c-98ae-4bda-b37f-b30d4b289a5b"
az account show --output table  # Verify subscription
```

### **2. Deploy HCS Family VM (Confirmed Working):**
```powershell
# Single VM deployment that WORKS
.\deploy_h_series_ib_win2019_enhanced.ps1 -VmSize "Standard_HC44-16rs" -VmCount 1 -Location "westus2" -ResourceGroupName "HSeries-IB-jacomini-westus2"
```

### **3. Verify Deployment:**
```powershell
# Check VM status
az vm show --resource-group "HSeries-IB-jacomini-westus2" --name "HSeries-IB1" --show-details --output table

# List all resources
az resource list --resource-group "HSeries-IB-jacomini-westus2" --output table
```

### **4. Test InfiniBand (Remote Commands):**
```powershell
# Check network adapters
az vm run-command invoke --resource-group "HSeries-IB-jacomini-westus2" --name "HSeries-IB1" --command-id "RunPowerShellScript" --scripts "Get-NetAdapter | Format-Table Name, InterfaceDescription, LinkSpeed -AutoSize"

# Check RDMA status  
az vm run-command invoke --resource-group "HSeries-IB-jacomini-westus2" --name "HSeries-IB1" --command-id "RunPowerShellScript" --scripts "Get-NetAdapterRdma | Format-Table Name, Enabled, MaxQueuePairs -AutoSize"

# Check SMB interfaces
az vm run-command invoke --resource-group "HSeries-IB-jacomini-westus2" --name "HSeries-IB1" --command-id "RunPowerShellScript" --scripts "Get-SmbClientNetworkInterface | Format-Table InterfaceIndex, InterfaceAlias, RdmaCapable, LinkSpeed -AutoSize"
```

### **5. Connect via RDP:**
```powershell
# Connect to VM
mstsc /v:4.155.210.177
# Username: azureuser
# Password: [your deployment password]
```

3. **Request Quota Increase** (For other H Family VMs):
   - Go to Azure Portal → Subscriptions → Usage + quotas
   - Search for "Standard H Family vCPUs" (for Standard_HC44rs, Standard_HB120-* series)
   - Request increase to at least 32 vCPUs (allows 2 × 16-vCPU VMs)
   - Typical approval time: 1-2 business days

2. **Check Current Quota Status**:
   ```powershell
   # Check H-series quota in current region (East US)
   az vm list-usage --location "eastus" --query "[?contains(name.value, 'H')]" --output table
   
   # Check quota in other regions
   az vm list-usage --location "westus2" --query "[?contains(name.value, 'H')]" --output table
   az vm list-usage --location "northeurope" --query "[?contains(name.value, 'H')]" --output table
   ```

3. **Try Different Regions**:
   ```powershell
   # Check quota in different regions
   .\deploy_h_series_ib_win2019_enhanced.ps1 -VmSize "HC44-16rs" -VmCount 1 -Location "eastus" -CheckQuota
   .\deploy_h_series_ib_win2019_enhanced.ps1 -VmSize "HB120-16rs_v3" -VmCount 1 -Location "westus2" -CheckQuota
   .\deploy_h_series_ib_win2019_enhanced.ps1 -VmSize "HB120-16rs_v3" -VmCount 1 -Location "northeurope" -CheckQuota
   .\deploy_h_series_ib_win2019_enhanced.ps1 -VmSize "HB120-16rs_v3" -VmCount 1 -Location "southcentralus" -CheckQuota
   ```

3. **Use Single VM for Testing**:
   ```powershell
   # Deploy just 1 VM (still needs 16 vCPUs)
   .\deploy_h_series_ib_win2019_enhanced.ps1 -VmSize "Standard_HB120-16rs_v3" -VmCount 1 -CheckQuota
   ```

**Note**: Unfortunately, there are no H-series VMs that fit within an 8 vCPU quota. H-series VMs are designed for HPC workloads and start at 16 vCPUs minimum.

### Common Issues:

1. **Driver installation fails:**
   - Check Windows updates are current
   - Verify VM size supports InfiniBand
   - Try manual driver installation

2. **RDMA not enabled:**
   - Ensure accelerated networking is enabled on NICs
   - Check if security features are interfering (script disables them)
   - Restart the VM after driver installation

3. **Connectivity issues:**
   - Verify network security group rules
   - Check if Windows Firewall is blocking traffic
   - Ensure VMs are in the same subnet

### Manual Driver Installation:
If automatic installation fails, you can manually install drivers:

1. Download: `https://content.mellanox.com/WinOF/MLNX_WinOF2-25_4_50020_All_x64.exe`
2. Run as Administrator with `/S /v/qn` flags for silent install
3. Restart the VM
4. Verify with `Get-NetAdapterRdma`

## Example Successful Deployment Session

### **Successful HCS Family Deployment (August 6, 2025)**

```powershell
PS> .\deploy_h_series_ib_win2019_enhanced.ps1 -VmSize "Standard_HC44-16rs" -VmCount 1 -Location "westus2" -ResourceGroupName "HSeries-IB-jacomini-westus2"

🚀 H Series VM with InfiniBand Deployment Script
================================================

Configuration:
  Resource Group: HSeries-IB-jacomini-westus2
  Location: westus2
  VM Size: Standard_HC44-16rs
  VM Count: 1
  VM Prefix: HSeries-IB
  Admin Username: azureuser
  OS: Windows Server 2019
  InfiniBand Driver: Mellanox WinOF-2

Selected VM Details:
  vCPUs: 16
  RAM: 352 GB
  InfiniBand: 100 Gbps HDR
  Estimated Cost: $0.80/hour per VM
  Total Estimated Cost: $0.80/hour for 1 VMs
  Description: Budget HCS Family option with reduced cores

🔑 Selecting Azure subscription...
Selected subscription: HPC & AI Support Team Shared (4ff8254c-98ae-4bda-b37f-b30d4b289a5b)

📋 Ensuring resource group exists...
✅ Creating resource group: HSeries-IB-jacomini-westus2

🌐 Setting up network infrastructure...
✅ Creating Network Security Group: HSeries-IB-NSG with InfiniBand rules
✅ Creating Virtual Network: HSeries-VNet

💻 Deploying H Series VMs...
✅ Creating VM: HSeries-IB1
✅ VM HSeries-IB1 created successfully

✅ H Series VM deployment with InfiniBand support completed!

# Verification Results:
PS> az vm show --resource-group "HSeries-IB-jacomini-westus2" --name "HSeries-IB1" --show-details --output table
Name         ResourceGroup                PowerState    PublicIps      Location    Zones
-----------  ---------------------------  ------------  -------------  ----------  -------
HSeries-IB1  HSeries-IB-jacomini-westus2  VM running    4.155.210.177  westus2

# InfiniBand Verification (via remote command):
Network Adapters Found:
- Ethernet   | Microsoft Hyper-V Network Adapter                 | 50 Gbps  | Up
- Ethernet 2 | Mellanox ConnectX-5 Virtual Adapter              | 100 Gbps | Up ✅
- Ethernet 4 | Mellanox ConnectX-4 Lx Virtual Ethernet Adapter | 50 Gbps  | Up ✅

RDMA Status:
- Ethernet 2: RDMA Enabled ✅
- Ethernet 4: RDMA Enabled ✅

SMB Network Interfaces:
- Interface 4: RDMA Capable (100 Gbps) ✅
```

### **Key Success Factors:**

1. **Subscription**: Used HPC & AI Support Team Shared (4ff8254c-98ae-4bda-b37f-b30d4b289a5b)
2. **VM Size**: Standard_HC44-16rs (HCS Family) - **Available with 1320 vCPU quota**
3. **Region**: West US 2 - **Feature propagation completed**
4. **Feature Registration**: Microsoft.Compute\UseStandardSecurityType registered
5. **Result**: **Two functional InfiniBand adapters** (100 Gbps + 50 Gbps) with RDMA enabled

## Cost Considerations

H series VMs are expensive. Consider these cost-saving strategies:

1. Use **Azure Spot VMs** for development/testing
2. **Auto-shutdown** VMs when not in use
3. **Deallocate** VMs rather than just stopping them
4. Use **smaller H series** sizes for testing (HB60rs vs HB120rs_v3)

## Next Steps

After deployment:

1. Install your HPC applications (MPI, computational software)
2. Configure MPI to use InfiniBand for inter-node communication
3. Run benchmarks to verify InfiniBand performance
4. Set up shared storage if needed (Azure NetApp Files, Azure Files)
5. Configure job scheduling software if required

## Support

For issues with:
- **Azure deployment**: Check Azure Activity Log in the portal
- **InfiniBand drivers**: Consult Mellanox documentation
- **VM performance**: Use Azure Monitor and VM insights
- **Network connectivity**: Check NSG rules and VM network configuration
