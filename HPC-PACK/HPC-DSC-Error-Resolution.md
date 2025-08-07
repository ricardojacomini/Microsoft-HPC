# HPC Pack DSC Extension Error Resolution Guide

## Error Overview

The error code `-532462766` in HPC Pack DSC extensions typically indicates:

```
VMExtensionProvisioningError: VM has reported a failure when processing extension 'setupHpcHeadNode'
DSC Configuration 'InstallPrimaryHeadNode' completed with error(s)
Failed to Install HPC Pack Head Node (errCode=-532462766)
```

## Root Causes

1. **Domain Configuration Issues**
   - Active Directory domain not properly created
   - DNS resolution problems
   - Domain join failures

2. **Permission Problems**
   - Insufficient privileges for HPC installation
   - Service account authentication failures
   - Key Vault access issues

3. **Resource Dependencies**
   - Missing Windows features/roles
   - Incomplete .NET Framework installation
   - SQL Server Express setup failures

4. **InfiniBand/RDMA Conflicts**
   - Driver compatibility issues on HB/HC series VMs
   - Trusted Launch security features blocking drivers
   - Accelerated networking configuration problems

## Resolution Steps

### Step 1: Use the Automated Fix Script

Run the troubleshooting script we created:

```powershell
.\Fix-HPCPackDSCError.ps1 -ResourceGroupName "your-rg-name" -AdminPassword (ConvertTo-SecureString "YourPassword" -AsPlainText -Force)
```

For InfiniBand-enabled clusters:
```powershell
.\Fix-HPCPackDSCError.ps1 -ResourceGroupName "your-rg-name" -AdminPassword (ConvertTo-SecureString "YourPassword" -AsPlainText -Force) -FixInfiniBand
```

### Step 2: Manual Verification Steps

If the automated fix doesn't resolve the issue:

1. **Check VM Extension Status**
   ```powershell
   Get-AzVMExtension -ResourceGroupName "your-rg" -VMName "headnode"
   ```

2. **Remove Failed Extensions**
   ```powershell
   Remove-AzVMExtension -ResourceGroupName "your-rg" -VMName "headnode" -Name "setupHpcHeadNode" -Force
   ```

3. **Verify Domain Configuration**
   Connect to the VM via RDP and check:
   - Computer is joined to the correct domain
   - DNS resolution works for domain services
   - Active Directory services are running

### Step 3: Alternative Deployment Approaches

#### Option A: Use Standard VM Sizes First
If using HB/HC series VMs, try deploying with standard VMs first:

```powershell
# Modify your deployment script parameters:
$parameters = @{
    # ... other parameters ...
    headNodeVMSize = "Standard_D4s_v3"  # Instead of HB120rs_v3
    computeNodeVMSize = "Standard_E4s_v3"  # Standard size
    enableAcceleratedNetworking = "No"
    autoInstallInfiniBandDriver = "No"
}
```

#### Option B: Manual HPC Pack Installation
1. Deploy base Windows VMs without HPC Pack
2. RDP to the head node
3. Download and run HPC Pack installer manually
4. Configure cluster through HPC Cluster Manager

### Step 4: InfiniBand-Specific Solutions

For HB120rs_v3 and other InfiniBand VMs:

1. **Disable Trusted Launch Security Features**
   ```json
   "securityProfile": {
       "uefiSettings": {
           "secureBootEnabled": false,
           "vTpmEnabled": false
       },
       "securityType": "TrustedLaunch"
   }
   ```

2. **Install Mellanox Drivers Post-Deployment**
   ```powershell
   # Use the Configure-InfiniBand function from deploy_hpc_pack_cluster_ib.ps1
   Configure-InfiniBand -ResourceGroup "your-rg" -VmPrefix "HPCNode" -VmCount 2 
       -DriverUrl "https://content.mellanox.com/WinOF/MLNX_WinOF2-25_4_50020_All_x64.exe" 
       -DriverInstaller "WinOF2-latest.exe" -DownloadPath "C:\Temp\Infiniband"
   ```

3. **Verify RDMA Capability**
   ```powershell
   Get-NetAdapterRdma | Where-Object { $_.Enabled -eq $true }
   ```

## Prevention Strategies

### For Future Deployments:

1. **Use Tested VM Sizes**
   - Start with Standard_D4s_v3 for head nodes
   - Use Standard_E4s_v3 for compute nodes
   - Add InfiniBand support after basic cluster works

2. **Implement Staging Approach**
   ```powershell
   # Stage 1: Deploy basic cluster
   .\deploy_hpc_pack_cluster_wn.ps1
   
   # Stage 2: Add InfiniBand nodes
   .\deploy_hpc_pack_cluster_ib.ps1 -WhatIf  # Test first
   .\deploy_hpc_pack_cluster_ib.ps1          # Deploy
   ```

3. **Monitor Extension Status**
   ```powershell
   # Check extension status during deployment
   $extensions = Get-AzVMExtension -ResourceGroupName $resourceGroup -VMName $vmName
   $extensions | Where-Object { $_.ProvisioningState -eq "Failed" }
   ```

## Troubleshooting Commands

### Check ARM Template Validation
```powershell
Test-AzResourceGroupDeployment -ResourceGroupName "your-rg" -TemplateFile "new-1hn-wincn-ad.json" -TemplateParameterObject $parameters
```

### View Deployment Operations
```powershell
Get-AzResourceGroupDeploymentOperation -ResourceGroupName "your-rg" -DeploymentName "your-deployment"
```

### Check VM Status
```powershell
Get-AzVM -ResourceGroupName "your-rg" -Name "headnode" -Status
```

## Known Working Configurations

### Basic HPC Pack (No InfiniBand)
```powershell
$parameters = @{
    headNodeVMSize = "Standard_D4s_v3"
    headNodeOS = "WindowsServer2022"
    computeNodeVMSize = "Standard_E2s_v3"
    enableAcceleratedNetworking = "No"
    autoInstallInfiniBandDriver = "No"
}
```

### InfiniBand-Enabled HPC Pack
```powershell
$parameters = @{
    headNodeVMSize = "Standard_D4s_v3"          # Non-IB head node
    computeNodeVMSize = "Standard_HB120rs_v3"   # IB compute nodes
    enableAcceleratedNetworking = "Yes"
    autoInstallInfiniBandDriver = "Yes"
}
```

## Additional Resources

- [HPC Pack Documentation](https://docs.microsoft.com/en-us/powershell/high-performance-computing/overview)
- [Azure HB-series VMs](https://docs.microsoft.com/en-us/azure/virtual-machines/hb-series)
- [InfiniBand Driver Installation](https://docs.microsoft.com/en-us/azure/virtual-machines/workloads/hpc/enable-infiniband)
- [DSC Extension Troubleshooting](https://aka.ms/VMExtensionDSCWindowsTroubleshoot)

## Contact Support

If issues persist after following this guide:
1. Gather deployment logs from Azure Portal
2. Run the diagnostic script with verbose output
3. Check VM Event Logs (System and Application)
4. Contact Azure Support with error details and resource IDs
