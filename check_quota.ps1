<#
.SYNOPSIS
    Self-contained Azure VM quota checker for HPC deployments. Scans specified regions for vCPU family quotas
    and estimates the maximum number of VMs deployable per VM size based on available family quotas.

.EXAMPLE
    .\check_quota.ps1

    Option 1: Temporarily bypass execution policy (run in an elevated PowerShell)
    powershell -ExecutionPolicy Bypass -File .\check_quota.ps1

    Option 2: Change Execution Policy (More Permanent)
    If you want to allow unsigned scripts to run more generally (e.g., for development or internal scripts), you can change the policy:
    PowerShellSet-ExecutionPolicy RemoteSigned -Scope CurrentUser

    Option 3: Unblock the Script File
    If the script was downloaded from the internet, it might be blocked. You can unblock it like this:
    PowerShellUnblock-File -Path .\check_quota.ps1

.NOTES
    Author         : Ricardo S Jacomini
    Team           : Azure HPC + AI  
    Email          : ricardo.jacomini@microsoft.com
    Version        : 1.6.0
    Last Modified  : 2025-09-02
    Script Name    : check_quota.ps1
    Tags           : quota, vmsize

.LINK
    Azure VM sizes overview
    https://learn.microsoft.com/en-us/azure/virtual-machines/sizes/overview?tabs=breakdownsize%2Cgeneralsizelist%2Ccomputesizelist%2Cmemorysizelist%2Cstoragesizelist%2Cgpusizelist%2Cfpgasizelist%2Chpcsizelist

.LINK
    Azure VM quotas (includes PowerShell and CLI)
    https://learn.microsoft.com/en-us/azure/virtual-machines/quotas?tabs=powershell
#>


param(
    # Fallback quota family when no pattern matches
    [string]$DefaultQuotaFamily = 'standardDFamily',
        # VM sizes to check: accept a list of size names OR a map { SizeName = vCPU }.
        # If a list is provided, vCPU will be auto-derived from the size name with Azure fallback when needed.
    [object]$VmSizes = @(
        'Standard_D4s_v3',
        'Standard_HB120rs_v3'
    ),
    # Regions to check for quota availability
    [string[]]$Regions = @(
        # US Regions
        'eastus','eastus2','westus','westus2','westus3','centralus','northcentralus','southcentralus','westcentralus',
        # Canada Regions
        'canadacentral','canadaeast',
        # Australia Regions
        'australiaeast','australiasoutheast','australiacentral','australiacentral2'
    )
)

# Helper to derive quota family from a VM size
function Get-QuotaFamilyName {
    param(
        [Parameter(Mandatory)][string]$VmSize,
        [string[]]$UsageNames
    )

    # Helper to find first matching quota family from available usage names
    function Find-FromUsage([string]$pattern) {
        if (-not $UsageNames) { return $null }
        $regex = [regex]::new($pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        return ($UsageNames | Where-Object { $regex.IsMatch($_) } | Select-Object -First 1)
    }

    # H family (CPU HPC): HB/HC/HX/H
    if ($VmSize -like 'Standard_HB*') {
        $m = Find-FromUsage '^standardHB.*Family$'; if ($m) { return $m } else { return 'standardHBv3Family' }
    }
    if ($VmSize -like 'Standard_HC*') {
        $m = Find-FromUsage '^standardHC.*Family$'; if ($m) { return $m } else { return $DefaultQuotaFamily }
    }
    if ($VmSize -like 'Standard_HX*') {
        $m = Find-FromUsage '^standardHX.*Family$'; if ($m) { return $m } else { return $DefaultQuotaFamily }
    }
    if ($VmSize -like 'Standard_H*') {
        $m = Find-FromUsage '^standardH(?!B|C|X).*Family$'; if ($m) { return $m } else { return $DefaultQuotaFamily }
    }

    # N family (GPU): NC/ND/NV
    if ($VmSize -like 'Standard_NC*') {
        $m = Find-FromUsage '^standardNC.*Family$'; if ($m) { return $m } else { return $DefaultQuotaFamily }
    }
    if ($VmSize -like 'Standard_ND*') {
        $m = Find-FromUsage '^standardND.*Family$'; if ($m) { return $m } else { return $DefaultQuotaFamily }
    }
    if ($VmSize -like 'Standard_NV*') {
        $m = Find-FromUsage '^standardNV.*Family$'; if ($m) { return $m } else { return $DefaultQuotaFamily }
    }
    if ($VmSize -like 'Standard_N*') {
        $m = Find-FromUsage '^standardN.*Family$'; if ($m) { return $m } else { return $DefaultQuotaFamily }
    }

    # Common D families
    if ($VmSize -like 'Standard_D*as_v5*') {
        $m = Find-FromUsage '^standardDASv5Family$'; if ($m) { return $m } else { return 'standardDASv5Family' }
    }
    if ($VmSize -like 'Standard_D*s_v5*') {
        $m = Find-FromUsage '^standardDSv5Family$'; if ($m) { return $m } else { return 'standardDSv5Family' }
    }
    if ($VmSize -like 'Standard_D*s_v3*') {
        $m = Find-FromUsage '^standardDSv3Family$'; if ($m) { return $m } else { return 'standardDSv3Family' }
    }

    # Fallback generic D family or default
    if ($VmSize -like 'Standard_D*') {
        $m = Find-FromUsage '^standardD.*Family$'; if ($m) { return $m } else { return $DefaultQuotaFamily }
    }

    return $DefaultQuotaFamily
}

# Attempt to parse vCPU count from a VM size name (e.g., Standard_D4s_v5 -> 4, Standard_HB120rs_v3 -> 120)
function Get-VcpuFromVmSizeName {
    param([Parameter(Mandatory)][string]$VmSize)
    try {
        $core = ($VmSize -replace '^Standard_', '')
        # Pattern: <Letters><Digits>... e.g., D4s_v5, HB120rs_v3, NC48ads_A100_v4
        $m = [regex]::Match($core, '^[A-Za-z]+(?<vcpu>\d+)')
        if ($m.Success) { return [int]$m.Groups['vcpu'].Value }
        # Fallback: first digit sequence anywhere
        $m2 = [regex]::Match($core, '(?<vcpu>\d+)')
        if ($m2.Success) { return [int]$m2.Groups['vcpu'].Value }
    } catch {}
    return $null
}

# Resolve vCPU count via Azure CLI for one of the regions (tries first few regions)
function Get-VcpuFromAz {
    param(
        [Parameter(Mandatory)][string]$VmSize,
        [Parameter(Mandatory)][string[]]$Regions
    )
    foreach ($r in ($Regions | Select-Object -First 3)) {
        try {
            $cores = az vm list-sizes --location $r --query "[?name=='$VmSize'].numberOfCores | [0]" --output tsv 2>$null
            if ($cores -and $cores -match '^\d+$') { return [int]$cores }
        } catch {}
    }
    return $null
}

# Define regions and VM sizes
Write-Host "Checking US, Canada, and Australia regions..." -ForegroundColor Green
$regions = $Regions

# Normalize VM sizes to a hashtable map { SizeName = vCPU }
$vmSizeMap = @{}
if ($VmSizes -is [hashtable]) {
    $vmSizeMap = $VmSizes
} else {
    foreach ($size in [System.Collections.IEnumerable]$VmSizes) {
        if (-not $size) { continue }
        $vcpu = Get-VcpuFromVmSizeName -VmSize $size
        if (-not $vcpu) { $vcpu = Get-VcpuFromAz -VmSize $size -Regions $regions }
        if ($vcpu) {
            $vmSizeMap[$size] = $vcpu
        } else {
            Write-Host ("  ⚠️  Could not determine vCPU count for {0}; defaulting to 1" -f $size) -ForegroundColor Yellow
            $vmSizeMap[$size] = 1
        }
    }
}

# Print VM sizes that will be searched
$vmCount = $vmSizeMap.Count
Write-Host ("VM sizes to search ({0}): {1}" -f $vmCount, ($vmSizeMap.Keys -join ', ')) -ForegroundColor Green
$vmSizeMap.GetEnumerator() | Sort-Object Key | ForEach-Object {
    Write-Host ("  - {0,-28} vCPU per VM: {1}" -f $_.Key, $_.Value) -ForegroundColor White
}

# Loop through each region
$regionCount = 0
$totalRegions = $regions.Count
Write-Host "Checking $totalRegions regions for VM quota availability..." -ForegroundColor Green

foreach ($region in $regions) {
    $regionCount++
    Write-Host "`n[$regionCount/$totalRegions] Region: $region" -ForegroundColor Cyan

    try {
        # Get usage data for the region
        $usage = az vm list-usage --location $region --query "[].{Name:name.value, Current:currentValue, Limit:limit}" --output json 2>$null | ConvertFrom-Json

        if (-not $usage) {
            Write-Host "  No quota data available for $region" -ForegroundColor Gray
            continue
        }

    foreach ($vm in $vmSizeMap.Keys) {
        $vcpuPerVM = $vmSizeMap[$vm]

    # Determine which quota name to look for (derived from VM size)
        $usageNames = $usage | Select-Object -ExpandProperty Name
        $quotaName = Get-QuotaFamilyName -VmSize $vm -UsageNames $usageNames

        # Find the quota entry
        $quota = $usage | Where-Object { $_.Name -eq $quotaName }

        if ($quota) {
            $available = $quota.Limit - $quota.Current
            $maxVMs = [math]::Floor($available / $vcpuPerVM)
            if ($maxVMs -gt 0) {
                Write-Host "  $vm -> Available vCPUs: $available -> Max VMs: $maxVMs" -ForegroundColor Green
            } else {
                Write-Host "  $vm -> Available vCPUs: $available -> Max VMs: $maxVMs" -ForegroundColor Red
            }
        } else {
            Write-Host "  $vm -> Quota info not found" -ForegroundColor Gray
        }
    }
    } catch {
        Write-Host "  Error checking region $region`: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "`n" + "="*80 -ForegroundColor Cyan

# Preserve input order when summarizing (list order; otherwise use map keys)
$vmOrder = @()
if ($VmSizes -is [hashtable]) { $vmOrder = @($vmSizeMap.Keys) } else { $vmOrder = @([System.Collections.IEnumerable]$VmSizes) }
if (-not $vmOrder -or $vmOrder.Count -eq 0) { $vmOrder = @($vmSizeMap.Keys) }

foreach ($vm in $vmOrder) {
    $vcpuPerVM = if ($vm -and $vmSizeMap.ContainsKey($vm)) { $vmSizeMap[$vm] } else { $null }

    Write-Host ("SUMMARY: Regions with available {0} quota:" -f $vm) -ForegroundColor Yellow
    if ($vcpuPerVM) { Write-Host ("(vCPUs per VM: {0})" -f $vcpuPerVM) -ForegroundColor DarkGray }
    Write-Host "="*80 -ForegroundColor Cyan

    $regionsWithVm = @()
    foreach ($region in $regions) {
        $usage = az vm list-usage --location $region --query "[].{Name:name.value, Current:currentValue, Limit:limit}" --output json 2>$null | ConvertFrom-Json
        if ($usage) {
            $usageNames = $usage | Select-Object -ExpandProperty Name
            $familyName = Get-QuotaFamilyName -VmSize $vm -UsageNames $usageNames
            $quota = $usage | Where-Object { $_.Name -eq $familyName }
            if ($quota -and $vcpuPerVM) {
                $available = $quota.Limit - $quota.Current
                $maxVMs = [math]::Floor($available / $vcpuPerVM)
                if ($maxVMs -gt 0) {
                    $regionsWithVm += ("{0} {1} {2} VMs available ({3} vCPUs)" -f $region, $maxVMs, $vm, $available)
                }
            }
        }
    }

    if ($regionsWithVm.Count -gt 0) {
        $regionsWithVm | ForEach-Object { Write-Host ("  [OK] {0}" -f $_) -ForegroundColor Green }
    } else {
        Write-Host ("  [NONE] No regions found with available {0} quota" -f $vm) -ForegroundColor Red
    }

    Write-Host "`nRECOMMENDATION:" -ForegroundColor Yellow
    if ($regionsWithVm.Count -gt 0) {
        Write-Host ("  Best regions for deploying {0}:" -f $vm) -ForegroundColor Green
        $regionsWithVm | ForEach-Object {
            $regionOnly = ($_ -split '\s+')[0]
            Write-Host ("     -> {0}" -f $regionOnly) -ForegroundColor Cyan
        }
    } else {
        Write-Host ("  Request a quota increase for the {0} family in your preferred region" -f (Get-QuotaFamilyName -VmSize $vm)) -ForegroundColor Yellow
        Write-Host "  Alternative: Use Standard_D8as_v5 for compute nodes (widely available)" -ForegroundColor Cyan
    }

    Write-Host ""  # blank line between VM sections
}

# Optional tip: check quota via Az PowerShell module
# Get-InstalledModule | Where-Object { $_.Name -like "*Az*" -or $_.Name -like "*AzureRM*" }
Write-Host "Tip: You can also check quota with Az PowerShell using Get-AzVMUsage." -ForegroundColor DarkGray
Write-Host 'Example: Get-AzVMUsage -Location "East US"' -ForegroundColor DarkGray