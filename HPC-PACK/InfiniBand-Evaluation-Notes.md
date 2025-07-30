# InfiniBand Deployment Evaluation Notes

## Basic RDMA and Network Adapter Diagnostics

### Essential PowerShell Commands for IB Verification

```powershell
# Check RDMA adapter status
Get-NetAdapterRdma

# Verify SMB client network interfaces
Get-SmbClientNetworkInterface

# Detailed Ethernet adapter information (typically "Ethernet 2" for IB)
Get-NetAdapter | Where-Object { $_.Name -eq "Ethernet 2" } | Format-List *

# Advanced adapter properties
Get-NetAdapterAdvancedProperty -Name "Ethernet 2"
```

### Mellanox ConnectX-6 Feature Analysis

```cmd
# Comprehensive feature dump for ConnectX-6 adapter
Mlx5Cmd.exe -Features -Name "Ethernet 2"
```

This command provides detailed information about how your ConnectX-6 adapter is configured and constrained in the current environment.

## 🔍 Key Feature Status Summary

| Feature | Status | Notes |
|---------|--------|-------|
| DevX | ❌ Disabled | Disabled via registry; DevX enables direct hardware access for advanced applications |
| ECE | ✅ Enabled | Enhanced Connection Establishment — good sign for RDMA |
| NDK | ✅ Enabled | Network Direct Kernel support — confirms RDMA functionality is up |
| VmQoS | ❌ Disabled | Likely not needed unless you're doing advanced traffic shaping across VFs |
| ZTT | ❌ Not Supported | Zero Touch Transport unsupported by current FW — not critical unless targeting low-latency telemetry |
| FW Tracer / Packet Monitor / DOCA Telemetry | ❌ Disabled | Debug/telemetry tools, might be limited by OS or FW build |
| Data Direct / VF CPU Monitor / MRC-VF / Ngauge | ❌ Disabled / Unsupported | Tied to advanced VM or multi-tenant acceleration scenarios |
| RFD Bulk Allocator | ❌ Disabled | Current buffer layout isn't compatible — not a performance blocker unless optimizing for throughput extremes |

## 🔧 Tuning and Optimization Considerations

### DevX Configuration
- **Purpose**: Enables direct hardware access for DOCA, libibverbs, or custom RDMA applications
- **Action**: Enable `DevxEnabled` in registry if experimenting with advanced RDMA applications
- **Impact**: Required for certain high-performance computing scenarios

### SR-IOV Configuration
- **Current State**: VF features disabled because SR-IOV isn't enabled
- **Requirement**: Enable in BIOS/firmware and guest configuration
- **Use Case**: Required for virtual function scenarios

### QoS Offload
- **Current State**: Disabled via registry
- **Impact**: Not a blocker unless targeting fine-grained traffic priority management

## 🧠 Performance Insights

### Positive Indicators
- **ECE Enabled**: Enhanced Connection Establishment supports RDMA operations
- **NDK Enabled**: Network Direct Kernel confirms RDMA functionality
- **RoCE Ready**: Configuration supports MPI, Lustre, and RDMA-based workloads

### Optimization Opportunities
- Most disabled features are either not relevant to typical HPC workloads or reflect deeper virtualization/telemetry layers
- Current configuration is optimal for standard HPC cluster operations

## Advanced Diagnostics

### Mellanox System Information Snapshot
```cmd
# Comprehensive system diagnostic utility
C:\Program Files\Mellanox\MLNX_WinOF2\Diagnostic Tools\MLNX_System_Snapshot.exe

# Alternative execution
MLNX_System_Snapshot.exe
```

### Performance Testing
```powershell
# File transfer performance measurement
Measure-Command { Copy-Item \\headnode\share\file.test C:\test }
```

## Troubleshooting Checklist

### Network Adapter Verification
1. Verify "Ethernet 2" adapter is present and configured
2. Check RDMA adapter status shows as enabled
3. Confirm SMB client network interfaces are properly configured
4. Validate advanced properties match expected IB configuration

### ConnectX-6 Feature Validation
1. Run Mlx5Cmd.exe feature analysis
2. Verify ECE and NDK are enabled
3. Check if DevX needs to be enabled for specific workloads
4. Confirm SR-IOV settings match deployment requirements

### Performance Validation
1. Run Mellanox system snapshot for comprehensive analysis
2. Execute file transfer performance tests
3. Monitor RDMA traffic during workload execution
4. Validate latency and throughput meet expectations

## Notes for Multi-Adapter Auditing

For environments with multiple adapters, consider creating PowerShell scripts to:
- Compare RDMA capabilities across adapters
- Audit feature consistency between nodes
- Automate performance baseline establishment
- Generate compliance reports for cluster configuration

## Registry Considerations

Key registry locations for advanced configuration:
- DevX settings
- QoS offload configuration
- Feature enablement flags
- Performance tuning parameters

*Always backup registry before making changes and test modifications in non-production environments first.*
