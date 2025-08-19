# GitHub Issue: Fix Hardcoded Disk Number in CreateADPDC.ps1 DSC Script

## Issue Title
Fix hardcoded DiskNumber=2 in CreateADPDC.ps1 causing deployment failures on certain VM configurations

## Issue Description

### Problem
The DSC script `CreateADPDC.ps1` in the HPC Pack template contains hardcoded references to `DiskNumber = 2` for data disk configuration. This causes deployment failures when:

1. VMs have different disk numbering schemes
2. Only one data disk is attached (appears as Disk 1 instead of Disk 2)
3. VM sizes with different network adapter configurations affect disk enumeration

### Affected Code Location
File: `SharedResources/Generated/CreateADPDC.ps1.zip` → `CreateADPDC.ps1`

**Lines 46-56:**
```powershell
xWaitforDisk Disk2
{
     DiskNumber = 2    # ← HARDCODED VALUE
     RetryIntervalSec =$RetryIntervalSec
     RetryCount = $RetryCount
}
xDisk HPCDataDisk
{
    DiskNumber = 2      # ← HARDCODED VALUE
    DriveLetter = "F"
    FSLabel = 'HPCData'
}
```

### Impact
- **Deployment Failures**: DSC extension fails when expected Disk 2 doesn't exist
- **VM Size Compatibility**: Affects Standard_D2s_v3, Standard_HB120rs_v3, and other VM sizes
- **User Experience**: Forces manual intervention and workarounds

### Error Examples
```
DSC Extension Error: Cannot find disk with number 2
VM Configuration: OS Disk (Disk 0) + Data Disk (Disk 1) = Only 2 disks total
Expected by Script: Disk 2 (which doesn't exist)
```

### Proposed Solution

Replace hardcoded disk numbers with dynamic disk detection:

```powershell
# Instead of hardcoded DiskNumber = 2, suggestion. 
xWaitforDisk DataDisk
{
     DiskNumber = (Get-Disk | Where-Object {$_.PartitionStyle -eq 'RAW' -and $_.Size -gt 30GB} | Select-Object -First 1).Number
     RetryIntervalSec = $RetryIntervalSec
     RetryCount = $RetryCount
}
xDisk HPCDataDisk
{
    DiskNumber = (Get-Disk | Where-Object {$_.PartitionStyle -eq 'RAW' -and $_.Size -gt 30GB} | Select-Object -First 1).Number
    DriveLetter = "F"
    FSLabel = 'HPCData'
}
```

**Alternative Approach:**
Add a parameter to make disk number configurable:

```powershell
param(
    [Parameter(Mandatory)]
    [String]$DomainName,
    
    [Parameter(Mandatory)]
    [System.Management.Automation.PSCredential]$Admincreds,
    
    [Int]$DataDiskNumber = 1,  # ← NEW PARAMETER WITH DEFAULT
    
    [String[]]$DnsForwarder = @("8.8.8.8"),
    [Int]$RetryCount = 20,
    [Int]$RetryIntervalSec = 30
)
```

### Environment Details
- **Template**: Azure HPC Pack 2019 Update 3
- **VM Sizes Affected**: Standard_D2s_v3, Standard_HB120rs_v3, others
- **Azure Region**: eastus (and likely others)
- **Deployment Method**: ARM/Bicep templates with DSC extension

### Workaround Used
Currently using modified local copy of CreateADPDC.ps1 with `DiskNumber = 1` for affected deployments.

### Request
Please update the DSC script to use dynamic disk detection or configurable disk numbers to improve compatibility across different VM configurations and deployment scenarios.

---

**Repository**: https://github.com/Azure/hpcpack-template
**File**: SharedResources/Generated/CreateADPDC.ps1.zip
**Priority**: Medium (affects deployment reliability)
**Labels**: bug, enhancement, dsc, deployment
