# H Series VM with InfiniBand Deployment - Usage Examples

## Overview
The `deploy_h_series_ib_win2019_enhanced.ps1` script creates Azure H series VMs with InfiniBand/RDMA support on Windows Server 2019 without HPC Pack dependencies. The enhanced version includes cost optimization features, quota checking, and pricing comparisons.

**Available Scripts:**
- `deploy_h_series_ib_win2019_enhanced.ps1` - Enhanced H-series VM deployment with HCS Family support, quota checking, and cost optimization
- `install-infiniband-rdma.ps1` - **Enhanced RDMA installation script with pre-installation verification** - automatically skips installation if RDMA is already working
- `deploy-windows-accelerated-networking.bicep` - **NEW: Regular Windows VMs with Accelerated Networking** (cost-effective alternative to HC series)
- `deploy-windows-accelerated-networking.ps1` - **NEW: PowerShell deployment script for Accelerated Networking VMs**

**✅ Enhanced Features:**
- **Smart Verification**: Automatically checks if RDMA is already configured before installation
- **Cost Optimization**: HCS Family support with 1320 vCPU quota availability
- **Zero Downtime**: Skips unnecessary installation on already-configured systems
- **Accelerated Networking Alternative**: Up to 30 Gbps performance with regular VMs at standard pricing

## Prerequisites
1. Azure PowerShell module installed: `Install-Module -Name Az`
2. Azure account with appropriate permissions
3. Connected to Azure: `Connect-AzAccount`

## Basic Usage

### Option 1: H-Series VMs with InfiniBand (Premium HPC Performance)

**Use Case**: Maximum network performance (100+ Gbps), HPC workloads requiring InfiniBand, MPI applications
**Cost**: Premium pricing ($0.80-$12.00/hour)
**Performance**: Up to 200 Gbps InfiniBand with RDMA

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

### Option 2: Regular Windows VMs with Accelerated Networking (Cost-Effective Alternative)

**Use Case**: High network performance applications, web servers, databases, general compute workloads
**Cost**: Standard VM pricing (significantly lower than H-series)
**Performance**: Up to 30 Gbps with Accelerated Networking (sufficient for most workloads)

### 1. Interactive deployment with Accelerated Networking
```powershell
.\deploy-windows-accelerated-networking.ps1
```

### 2. Specific VM size with high performance
```powershell
.\deploy-windows-accelerated-networking.ps1 -VmSize "Standard_D8s_v3" -VmCount 3
```

### 3. Test deployment (validation only)
```powershell
.\deploy-windows-accelerated-networking.ps1 -WhatIf
```

### 4. Custom configuration with Windows Server 2019
```powershell
.\deploy-windows-accelerated-networking.ps1 -ResourceGroupName "MyApp-RG" -WindowsVersion "2019-datacenter" -VmCount 2
```

### 5. High-performance compute workload
```powershell
.\deploy-windows-accelerated-networking.ps1 -VmSize "Standard_F16s_v2" -EnablePremiumStorage $true -OsDiskSizeGB 256
```

### 6. Direct Bicep deployment
```bash
az deployment group create \
  --resource-group rg-win-accel \
  --template-file deploy-windows-accelerated-networking.bicep \
  --parameters @deploy-hseries-infiniband.parameters.json
```

## Parameters

### H-Series InfiniBand Deployment Parameters

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

### Accelerated Networking Deployment Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-ResourceGroupName` | `""` | Name of the resource group to create/use (interactive if not specified) |
| `-Location` | `eastus` | Azure region for deployment |
| `-ResourcePrefix` | `win-accel` | Prefix for all resource names |
| `-VmSize` | `Standard_D4s_v3` | VM size (must support Accelerated Networking) |
| `-WindowsVersion` | `2022-datacenter-azure-edition` | Windows Server version |
| `-VmCount` | `1` | Number of VMs to deploy |
| `-AdminUsername` | `azureuser` | Administrator username for all VMs |
| `-EnablePremiumStorage` | `true` | Use Premium SSD storage |
| `-OsDiskSizeGB` | `128` | OS disk size in GB |
| `-WhatIf` | `false` | Preview deployment without creating resources |

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

## Deployment Options Comparison

| Feature | H-Series with InfiniBand | Regular VMs with Accelerated Networking |
|---------|-------------------------|----------------------------------------|
| **Max Network Performance** | 200 Gbps InfiniBand + RDMA | 30 Gbps Ethernet |
| **Cost** | Premium ($0.80-$12/hour) | Standard VM pricing (much lower) |
| **Use Cases** | HPC, MPI, Scientific Computing | Web apps, databases, general compute |
| **Availability** | Limited regions, quota restrictions | Most regions, standard quotas |
| **Setup Complexity** | Complex (InfiniBand drivers) | Simple (built-in Azure feature) |
| **VM Size Options** | H/HC/HB series only | D, E, F series (wide selection) |
| **Recommended For** | Maximum performance requirements | Cost-conscious high-performance needs |

## Accelerated Networking Supported VM Sizes

The `deploy-windows-accelerated-networking.bicep` template supports these VM sizes with expected performance:

### **General Purpose (D-Series)**
| VM Size | vCPUs | RAM | Expected Bandwidth | Max PPS | Approx. Cost/Hour |
|---------|--------|-----|-------------------|---------|-------------------|
| `Standard_D2s_v3` | 2 | 8 GB | 1 Gbps | 125K | ~$0.10 |
| `Standard_D4s_v3` | 4 | 16 GB | 2 Gbps | 250K | ~$0.20 |
| `Standard_D8s_v3` | 8 | 32 GB | 4 Gbps | 500K | ~$0.40 |
| `Standard_D16s_v3` | 16 | 64 GB | 8 Gbps | 1M | ~$0.80 |
| `Standard_D32s_v3` | 32 | 128 GB | 16 Gbps | 2M | ~$1.60 |

### **Compute Optimized (F-Series)**
| VM Size | vCPUs | RAM | Expected Bandwidth | Max PPS | Approx. Cost/Hour |
|---------|--------|-----|-------------------|---------|-------------------|
| `Standard_F4s_v2` | 4 | 8 GB | 2 Gbps | 250K | ~$0.18 |
| `Standard_F8s_v2` | 8 | 16 GB | 4 Gbps | 500K | ~$0.36 |
| `Standard_F16s_v2` | 16 | 32 GB | 8 Gbps | 1M | ~$0.72 |
| `Standard_F32s_v2` | 32 | 64 GB | 16 Gbps | 2M | ~$1.44 |

### **Memory Optimized (E-Series)**
| VM Size | vCPUs | RAM | Expected Bandwidth | Max PPS | Approx. Cost/Hour |
|---------|--------|-----|-------------------|---------|-------------------|
| `Standard_E4s_v3` | 4 | 32 GB | 2 Gbps | 250K | ~$0.25 |
| `Standard_E8s_v3` | 8 | 64 GB | 4 Gbps | 500K | ~$0.50 |
| `Standard_E16s_v3` | 16 | 128 GB | 8 Gbps | 1M | ~$1.00 |
| `Standard_E32s_v3` | 32 | 256 GB | 16 Gbps | 2M | ~$2.00 |

**💡 Cost Comparison**: A `Standard_D8s_v3` with 4 Gbps Accelerated Networking costs ~$0.40/hour vs. HC-series at $0.80-$12.00/hour - **significant savings for most workloads!**

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

### For H-Series VMs with InfiniBand:

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

### For Regular VMs with Accelerated Networking:

After deployment, connect to the VMs and run these commands to verify Accelerated Networking:

```powershell
# Check network adapters and their capabilities
Get-NetAdapter | Select-Object Name, InterfaceDescription, LinkSpeed, Status

# Verify offload features (should show various offloads enabled)
Get-NetAdapterAdvancedProperty | Where-Object {$_.DisplayName -like '*Offload*'}

# Check for SR-IOV support (indicates Accelerated Networking)
Get-NetAdapterSriov

# Test network connectivity with detailed information
Test-NetConnection -ComputerName 8.8.8.8 -InformationLevel Detailed

# Check specific offload settings
Get-NetAdapterAdvancedProperty | Where-Object {
    $_.DisplayName -like '*Checksum*' -or 
    $_.DisplayName -like '*Scaling*' -or 
    $_.DisplayName -like '*Offload*'
} | Select-Object DisplayName, DisplayValue

# Network performance monitoring
Get-Counter "\Network Interface(*)\Bytes Total/sec" -SampleInterval 1 -MaxSamples 5
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

## 🤔 Which Deployment Option Should You Choose?

### Choose **H-Series with InfiniBand** when you need:
- ✅ **Maximum network performance** (100-200 Gbps)
- ✅ **RDMA capabilities** for ultra-low latency
- ✅ **MPI applications** that require InfiniBand
- ✅ **Scientific computing** workloads
- ✅ **Computational fluid dynamics, weather modeling**
- ✅ **Budget allows premium pricing** ($0.80-$12.00/hour)

### Choose **Regular VMs with Accelerated Networking** when you need:
- ✅ **High network performance** but not maximum (up to 30 Gbps)
- ✅ **Cost-effective solution** (significantly lower pricing)
- ✅ **Standard applications** (web servers, databases, APIs)
- ✅ **Development and testing** environments
- ✅ **General compute workloads** with network optimization
- ✅ **Quick deployment** without complex driver management
- ✅ **Wide VM size selection** (D, E, F series)

### Quick Decision Matrix:

| Your Requirement | Recommended Option |
|------------------|-------------------|
| **"I need the absolute fastest network performance"** | H-Series InfiniBand |
| **"I want good network performance at reasonable cost"** | Accelerated Networking |
| **"I'm running MPI/HPC applications"** | H-Series InfiniBand |
| **"I'm hosting web applications or databases"** | Accelerated Networking |
| **"Budget is a primary concern"** | Accelerated Networking |
| **"I need this for development/testing"** | Accelerated Networking |
| **"I require RDMA capabilities"** | H-Series InfiniBand |
| **"I want simple, reliable deployment"** | Accelerated Networking |

**💡 Pro Tip**: Start with **Accelerated Networking** for most workloads. It provides excellent performance at a fraction of the cost. Only move to H-Series if you specifically need InfiniBand/RDMA capabilities or maximum network throughput.

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
az account set --subscription "xxf8254c-blabla-4bda-b37f-b30d4b289ayy"
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
# Define variables
$resourceGroup = "HSeries-IB-jacomini-westus2"
$vmName = "HSeries-IB1"

# Check network adapters
az vm run-command invoke `
  --resource-group $resourceGroup `
  --name $vmName `
  --command-id "RunPowerShellScript" `
  --scripts "Get-NetAdapter | Format-Table Name, InterfaceDescription, LinkSpeed -AutoSize"

# Check RDMA status
az vm run-command invoke `
  --resource-group $resourceGroup `
  --name $vmName `
  --command-id "RunPowerShellScript" `
  --scripts "Get-NetAdapterRdma | Format-Table Name, Enabled, MaxQueuePairs -AutoSize"

# RDMA verification
az vm run-command invoke `
  --resource-group $resourceGroup `
  --name $vmName `
  --command-id "RunPowerShellScript" `
  --scripts "Get-NetAdapterRdma | Format-Table Name, Enabled, MaxQueuePairs -AutoSize; Write-Output '---'; Get-NetAdapter | Where-Object { `$_.InterfaceDescription -like '*Mellanox*' } | Format-Table Name, InterfaceDescription, LinkSpeed, Status -AutoSize; Write-Output '---'; Get-SmbClientNetworkInterface | Where-Object { `$_.RdmaCapable -eq `$true } | Format-Table InterfaceIndex, RdmaCapable, RssCapable -AutoSize" `
  --output table

# Check SMB interfaces
az vm run-command invoke `
  --resource-group $resourceGroup `
  --name $vmName `
  --command-id "RunPowerShellScript" `
  --scripts "Get-SmbClientNetworkInterface | Format-Table InterfaceIndex, InterfaceAlias, RdmaCapable, LinkSpeed -AutoSize"

```

### **5. Connect via RDP:**
```powershell
# Connect to VM
mstsc /v:4.155.210.177
# Username: azureuser
# Password: [your deployment password]
```

### **6. Standalone RDMA Installation with Smart Verification:**
```powershell
# The enhanced script automatically checks if RDMA is already working
# If RDMA is properly configured, installation is skipped automatically

# Remote execution with automatic verification
.\install-infiniband-rdma.ps1 -RemoteExecution -ResourceGroup "HSeries-IB-jacomini-westus2" -VmName "HSeries-IB1"

# Local execution with verification
.\install-infiniband-rdma.ps1

# The script will output:
# ✅ RDMA is already properly configured and working!
# ℹ️  Installation step will be skipped.
# ✅ System verification completed - RDMA is ready for use!
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

#### H-Series InfiniBand Issues:

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

#### Accelerated Networking Issues:

1. **Accelerated Networking not enabled:**
   - **Problem**: VM size doesn't support Accelerated Networking
   - **Solution**: Choose supported VM size (D2s_v3 or larger, F2s_v2 or larger)
   - **Verification**: Run `Get-NetAdapterSriov` - should show SR-IOV capabilities

2. **Lower than expected performance:**
   - **Check**: VM size limits - smaller VMs have lower network caps
   - **Verify**: No bandwidth throttling: `Get-NetAdapterAdvancedProperty | Where-Object {$_.DisplayName -like '*Throttl*'}`
   - **Optimize**: Enable RSS: `Set-NetAdapterAdvancedProperty -DisplayName 'Receive Side Scaling' -DisplayValue 'Enabled'`

3. **Deployment fails with "VM size not available":**
   - **Try different region**: Some regions have better VM availability
   - **Check quotas**: Standard VM quotas are usually sufficient
   - **Alternative sizes**: Switch between D, E, F series as needed

4. **Network performance not meeting expectations:**
   - **Check VM size**: Ensure you're using appropriate size for expected performance
   - **Verify offloads**: Use verification commands to ensure offloads are enabled
   - **Network testing**: Use tools like `iperf3` or `ntttcp` for actual throughput testing
   - **Monitor**: Use Azure Monitor Network Insights for performance analysis

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
