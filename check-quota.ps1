<#
.SYNOPSIS
    Self-contained Azure VM quota checker for HPC deployments. Scans specified regions for vCPU family quotas
    and estimates the maximum number of VMs deployable per VM size based on available family quotas.

.EXAMPLE
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass 
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
    Script Name    : check_quota_price.ps1
    Tags           : quota, vmsize, price and memory
D2ahs_v4
.LINK
    Azure VM sizes overview
    https://learn.microsoft.com/en-us/azure/virtual-machines/sizes/overview?tabs=breakdownsize%2Cgeneralsizelist%2Ccomputesizelist%2Cmemorysizelist%2Cstoragesizelist%2Cgpusizelist%2Cfpgasizelist%2Chpcsizelist

.LINK
    Azure VM quotas (includes PowerShell and CLI)
    https://learn.microsoft.com/en-us/azure/virtual-machines/quotas?tabs=powershell
#
# DISCLAIMER: This script is for informational purposes only and is NOT the official
# Azure Spot Advisor. Spot price and availability may change frequently. For official
# guidance on Spot VMs, eviction policies and recommended configurations, see:
# https://azure.microsoft.com/en-us/pricing/spot-advisor/
#
#>



param(
    # Fallback quota family when no pattern matches
    [string]$DefaultQuotaFamily = 'standardDFamily',
        # VM sizes to check: accept a list of size names OR a map { SizeName = vCPU }.
        # If a list is provided, vCPU will be auto-derived from the size name with Azure fallback when needed.
    [object]$VmSizes = @(
        'Standard_HB120rs_v3',
        'Standard_E64ds_v5',
        'Standard_E64ds_v4',
        'Standard_E64ds_v6'
    ),
    # Regions to check for quota availability
    [string[]]$Regions = @(
        # US Regions
        'eastus'#,'eastus2','westus','westus2','westus3','centralus','northcentralus','southcentralus','westcentralus',
        # Canada Regions
        #'canadacentral','canadaeast',
        # Australia Regions
        #'australiaeast','australiasoutheast','australiacentral','australiacentral2'
    )
    ,
    # Operating system for price lookup ('Linux' or 'Windows')
    [ValidateSet('Linux','Windows')][string]$Os = 'Linux'
    ,
    # Debug flag to print which Retail Prices API entry was selected for each price lookup
    [switch]$DebugPricing
    ,
    # Optional: Dump matching Retail Prices API items for the specified VM name (global). Useful to inspect candidates.
    [string]$DumpPricesFor = $null
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

# Resolve memory (GB) via Azure CLI for one of the regions (tries first few regions)
function Get-MemoryFromAz {
    param(
        [Parameter(Mandatory)][string]$VmSize,
        [Parameter(Mandatory)][string[]]$Regions
    )
    foreach ($r in ($Regions | Select-Object -First 3)) {
        try {
            $mem = az vm list-sizes --location $r --query "[?name=='$VmSize'].memoryInMb | [0]" --output tsv 2>$null
            if ($mem -and $mem -match '^\d+$') { return [math]::Round([decimal]$mem/1024, 2) }
        } catch {}
    }
    return $null
}

# Define regions and VM sizes
Write-Host "Checking Availability SKU for $Os OS..." -ForegroundColor Green
$regions = $Regions

# If requested, dump matching price items and exit early
if ($DumpPricesFor) {
    Dump-PriceItemsFor -Term $DumpPricesFor -Top 40
    return
}

# Normalize VM sizes to a hashtable map { SizeName = vCPU }
$vmSizeMap = @{}
$vmMemoryMap = @{}
if ($VmSizes -is [hashtable]) {
    $vmSizeMap = $VmSizes
} else {
    foreach ($size in [System.Collections.IEnumerable]$VmSizes) {
        if (-not $size) { continue }
        $vcpu = Get-VcpuFromVmSizeName -VmSize $size
        if (-not $vcpu) { $vcpu = Get-VcpuFromAz -VmSize $size -Regions $regions }
        if ($vcpu) {
            $vmSizeMap[$size] = $vcpu
            # attempt to resolve memory in GB
            $mem = Get-MemoryFromAz -VmSize $size -Regions $regions
            if ($mem) { $vmMemoryMap[$size] = $mem } else { $vmMemoryMap[$size] = $null }
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
    $key = $_.Key
    if (-not $key) { return }
    $memVal = $vmMemoryMap[$key]
    # If memory wasn't found via Azure, add known fallback values for common sizes
    if (-not $memVal) {
        switch -Wildcard ($key) {
            'Standard_HB120rs_v3' { $vmMemoryMap[$key] = 466944/1024; $memVal = $vmMemoryMap[$key]; break }
            'Standard_D8as_v5*' { $vmMemoryMap[$key] = 32768/1024; $memVal = $vmMemoryMap[$key]; break }
            'Standard_D2s_v5' { $vmMemoryMap[$key] = 8192/1024; $memVal = $vmMemoryMap[$key]; break }
            'Standard_E64ds_v4' { $vmMemoryMap[$key] = 516096/1024; $memVal = $vmMemoryMap[$key]; break }
            'Standard_E64ds_v5' { $vmMemoryMap[$key] = 516096/1024; $memVal = $vmMemoryMap[$key]; break }
            'Standard_E64ds_v6' { $vmMemoryMap[$key] = 516096/1024; $memVal = $vmMemoryMap[$key]; break }
            default { }
        }
    }
    if ($memVal) { $memText = ("{0} GB" -f $memVal) } else { $memText = 'N/A' }
    Write-Host ("  - {0,-28} vCPU per VM: {1,-3}  Memory: {2,-8}" -f $_.Key, $_.Value, $memText) -ForegroundColor White
}

# Pricing cache: map { vmSize -> pricePerHourUSD }
# Pricing cache: map { "region|vmSize|os" -> pricePerHourUSD }
$PriceCache = @{}

# Price metadata cache: map { "region|vmSize|os|priceType" -> @{ meterId=.. ; meterName=.. ; productName=.. } }
$PriceMetaCache = @{}

# Function: Get hourly price in USD for a VM size using Azure Retail Prices API
function Get-PriceForVmSize {
    param(
        [Parameter(Mandatory)][string]$VmSize,
        [Parameter(Mandatory)][string]$Region,
        [string]$PriceType = 'Consumption'  # e.g., 'Consumption' or 'Spot'
    )

    $cacheKey = "$Region|$VmSize|$Os|$PriceType"
    if ($PriceCache.ContainsKey($cacheKey)) {
        return $PriceCache[$cacheKey]
    }

    # Build filter: productName contains 'Virtual Machines', armRegionName equals region, skuName equals VmSize
    $filter = "serviceFamily eq 'Compute' and armRegionName eq '$Region' and skuName eq '$VmSize' and priceType eq '$PriceType'"
    $url = "https://prices.azure.com/api/retail/prices?`$filter=$([uri]::EscapeDataString($filter))"
    try {
        $response = Invoke-RestMethod -Uri $url -Method Get -UseBasicParsing -ErrorAction Stop
        # Normalize VM name for broader matching (e.g., 'Standard_HB120rs_v3' -> 'HB120rs v3')
        $normalizedVm = $VmSize -replace '^Standard_', '' -replace '_', ' '
        # If no items are returned from the strict skuName filter, retry with a broader contains(...) filter
        if ((-not $response.Items) -or ($response.Items.Count -eq 0)) {
            $broadFilter = "serviceFamily eq 'Compute' and armRegionName eq '$Region' and priceType eq '$PriceType' and (contains(productName,'$VmSize') or contains(skuName,'$VmSize') or contains(meterName,'$VmSize') or contains(productName,'$normalizedVm') or contains(meterName,'$normalizedVm'))"
            $broadUrl = "https://prices.azure.com/api/retail/prices?`$filter=$([uri]::EscapeDataString($broadFilter))"
            try {
                $broadResponse = Invoke-RestMethod -Uri $broadUrl -Method Get -UseBasicParsing -ErrorAction Stop
                if ($broadResponse.Items -and $broadResponse.Items.Count -gt 0) { $response = $broadResponse }
            } catch {}
        }
            # If still empty, try removing priceType constraint to discover candidate items
            if ((-not $response.Items) -or ($response.Items.Count -eq 0)) {
                $noTypeFilter = "serviceFamily eq 'Compute' and armRegionName eq '$Region' and (contains(productName,'$VmSize') or contains(skuName,'$VmSize') or contains(meterName,'$VmSize') or contains(productName,'$normalizedVm') or contains(meterName,'$normalizedVm'))"
                $noTypeUrl = "https://prices.azure.com/api/retail/prices?`$filter=$([uri]::EscapeDataString($noTypeFilter))"
                if ($DebugPricing) { Write-Host "    [DEBUG] Retry with no priceType filter: $noTypeUrl" -ForegroundColor DarkGray }
                try {
                    $noTypeResp = Invoke-RestMethod -Uri $noTypeUrl -Method Get -UseBasicParsing -ErrorAction Stop
                    if ($noTypeResp.Items -and $noTypeResp.Items.Count -gt 0) { $response = $noTypeResp }
                    else {
                        # As a last resort, try a global search (no region) to find possible SKU entries
                        $globalFilter = "serviceFamily eq 'Compute' and (contains(productName,'$VmSize') or contains(skuName,'$VmSize') or contains(meterName,'$VmSize') or contains(productName,'$normalizedVm') or contains(meterName,'$normalizedVm'))"
                        $globalUrl = "https://prices.azure.com/api/retail/prices?`$filter=$([uri]::EscapeDataString($globalFilter))"
                        if ($DebugPricing) { Write-Host "    [DEBUG] Retry global filter (no region): $globalUrl" -ForegroundColor DarkGray }
                        try {
                            $globalResp = Invoke-RestMethod -Uri $globalUrl -Method Get -UseBasicParsing -ErrorAction Stop
                            if ($globalResp.Items -and $globalResp.Items.Count -gt 0) { $response = $globalResp }
                        } catch {}
                    }
                } catch {}
            }
        # Response returns 'Items' array. Pick first matching item with unitPrice
        if ($response.Items -and $response.Items.Count -gt 0) {
            # Prefer hourly priced items in USD and matching OS
            $itemsUsd = $response.Items | Where-Object { ($_.unitOfMeasure -match 'Hour') -and ($_.currencyCode -eq 'USD') }
            # Narrow to the requested priceType (Consumption or Spot) when present
            $itemsUsd = $itemsUsd | Where-Object { ($_.priceType -and ($_.priceType -ieq $PriceType)) -or (-not $_.priceType) }
            # Exclude obvious Low Priority/Spot descriptors when priceType is Consumption
            if ($PriceType -ieq 'Consumption') {
                $itemsUsd = $itemsUsd | Where-Object { ($_.skuName -notmatch 'Low Priority|LowPriority|Low_Priority|Spot') -and ($_.meterName -notmatch 'Low Priority|Spot') -and ($_.productName -notmatch 'Low Priority|Spot') }
            }
            if ($itemsUsd -and $itemsUsd.Count -gt 0) {
                # Try a set of increasingly broad matches to pick the most representative price
                # 1) exact skuName
                $item = $itemsUsd | Where-Object { $_.skuName -ieq $VmSize } | Select-Object -First 1
                # 2) armSkuName if present
                if (-not $item) { $item = $itemsUsd | Where-Object { $_.armSkuName -and ($_.armSkuName -ieq $VmSize) } | Select-Object -First 1 }
                # 3) meterName contains VmSize
                if (-not $item) { $item = $itemsUsd | Where-Object { $_.meterName -and ($_.meterName -match $VmSize) } | Select-Object -First 1 }
                # 4) productName contains VmSize
                if (-not $item) { $item = $itemsUsd | Where-Object { $_.productName -and ($_.productName -match $VmSize) } | Select-Object -First 1 }
                # 5) OS-specific preferences
                if (-not $item) {
                    if ($Os -eq 'Linux') {
                        # prefer entries that explicitly reference Linux and avoid Windows or low-priority SKUs
                        $linuxCandidates = $itemsUsd | Where-Object { ($_.productName -match 'Linux' -or $_.meterName -match 'Linux' -or ($_.productName -notmatch 'Windows')) -and ($_.skuName -notmatch 'Low Priority|LowPriority|Low_Priority|DevTest') }
                        if ($linuxCandidates -and $linuxCandidates.Count -gt 0) {
                            # prefer the lowest priced Linux consumption SKU (typically the canonical on-demand Linux price)
                            $item = $linuxCandidates | Sort-Object -Property @{Expression={[decimal]$_.unitPrice}} | Select-Object -First 1
                        } else {
                            # If no Linux candidates in the region, perform a global sku search and pick the lowest-priced on-demand item
                            $globalSkuFilter = "serviceFamily eq 'Compute' and (contains(productName,'$VmSize') or contains(skuName,'$VmSize') or contains(meterName,'$VmSize') or contains(productName,'$normalizedVm') or contains(meterName,'$normalizedVm')) and priceType eq '$PriceType'"
                            $globalSkuUrl = "https://prices.azure.com/api/retail/prices?`$filter=$([uri]::EscapeDataString($globalSkuFilter))"
                            if ($DebugPricing) { Write-Host "    [DEBUG] No local Linux candidates; retry global sku query: $globalSkuUrl" -ForegroundColor DarkGray }
                            try {
                                $gResp = Invoke-RestMethod -Uri $globalSkuUrl -Method Get -UseBasicParsing -ErrorAction Stop
                                $gItems = $gResp.Items | Where-Object { ($_.unitOfMeasure -match 'Hour') -and ($_.currencyCode -eq 'USD') }
                                if ($gItems -and $gItems.Count -gt 0) {
                                    # choose the lowest priced item among available global candidates (likely the Linux on-demand price)
                                    $item = $gItems | Sort-Object -Property @{Expression={[decimal]$_.unitPrice}} | Select-Object -First 1
                                }
                            } catch {}
                        }
                    } else {
                        $item = $itemsUsd | Where-Object { $_.meterName -match 'Windows' } | Select-Object -First 1
                    }
                }
                # 6) If still multiple candidates, pick the one with the largest price (avoid small unrelated charges)
                # For Linux, avoid replacing with the largest price (Windows often higher). Only replace for non-Linux selections.
                if ($item -and $itemsUsd.Count -gt 1 -and $Os -ne 'Linux') {
                    $candidate = $itemsUsd | Sort-Object -Property @{Expression={[decimal]$_.unitPrice}} -Descending | Select-Object -First 1
                    if ($candidate -and $candidate.unitPrice -gt $item.unitPrice) { $item = $candidate }
                }
            }
            if (-not $item) { $item = $response.Items | Select-Object -First 1 }
                if ($item) {
                    $priceValue = $item.unitPrice
                    if ($null -ne $priceValue) {
                        $price = [decimal]$priceValue
                        # Store metadata for auditing
                        $meta = @{ meterId = $item.meterId; meterName = $item.meterName; productName = $item.productName; skuName = $item.skuName }
                        $PriceMetaCache[$cacheKey] = $meta
                        # Cache and return
                        $PriceCache[$cacheKey] = $price
                        if ($DebugPricing) {
                            $dbg = ('    [DEBUG] Selected price metadata for {0}`n      meterId: {1}`n      meterName: {2}`n      productName: {3}`n      skuName: {4}' -f $cacheKey, $meta.meterId, $meta.meterName, $meta.productName, $meta.skuName)
                            Write-Host $dbg -ForegroundColor DarkCyan
                        }
                        return $price
                    }
                }
        }
    } catch {
        # Quiet failure; cache 'null' to avoid repeated failing calls
        $PriceCache[$cacheKey] = $null
        return $null
    }

    $PriceCache[$cacheKey] = $null
    return $null
}

# Dump matching price entries for a term (global) -- used for debugging
function Dump-PriceItemsFor {
    param(
        [Parameter(Mandatory)][string]$Term,
        [int]$Top = 20
    )
    # Normalize
    $norm = $Term -replace '^Standard_', '' -replace '_', ' '
    $filter = "serviceFamily eq 'Compute' and (contains(productName,'$Term') or contains(skuName,'$Term') or contains(meterName,'$Term') or contains(productName,'$norm') or contains(meterName,'$norm'))"
    $url = "https://prices.azure.com/api/retail/prices?`$filter=$([uri]::EscapeDataString($filter))"
    Write-Host "Dumping top $Top matching Retail Prices items for term: $Term" -ForegroundColor Cyan
    Write-Host "Query: $url" -ForegroundColor DarkGray
    try {
        $resp = Invoke-RestMethod -Uri $url -Method Get -ErrorAction Stop
        if (-not $resp.Items -or $resp.Items.Count -eq 0) { Write-Host "No items found." -ForegroundColor Yellow; return }
        $resp.Items | Select-Object skuName, meterName, productName, unitPrice, priceType, armRegionName | Select-Object -First $Top | Format-Table -AutoSize
    } catch {
        Write-Host "Error querying Retail Prices API: $($_.Exception.Message)" -ForegroundColor Red
    }
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
            # Attempt to fetch price (first region used) and format, also fetch spot price
            $price = Get-PriceForVmSize -VmSize $vm -Region $region -PriceType 'Consumption'
            $spotPrice = Get-PriceForVmSize -VmSize $vm -Region $region -PriceType 'Spot'
            # Ensure memory is available; try to fetch memory in this region if missing
            if (-not $vmMemoryMap.ContainsKey($vm) -or -not $vmMemoryMap[$vm]) {
                $mem = Get-MemoryFromAz -VmSize $vm -Regions @($region)
            }
            $memVal = if ($vmMemoryMap.ContainsKey($vm)) { $vmMemoryMap[$vm] } else { $null }
            if ($memVal) { $memText = ("{0} GB" -f $memVal) } else { $memText = 'N/A' }
            if ($price) { $priceText = ("{0:0.000}" -f $price); $priceMonth = ("{0:0.00}" -f ($price * 730)) } else { $priceText = 'N/A'; $priceMonth = 'N/A' }
            if ($spotPrice) { $spotPriceText = ("{0:0.000}" -f $spotPrice); $spotPriceMonth = ("{0:0.00}" -f ($spotPrice * 730)) } else { $spotPriceText = 'N/A'; $spotPriceMonth = 'N/A' }
            if ($maxVMs -gt 0) {
                Write-Host ("  {0,-28} Memory: {1,-8} vCPUs: {2,5} -> Max VMs: {3,6}  $/hr (USD): {4}  $/mo (USD): {6,10}  Spot/hr (USD): {5}  Spot/mo (USD): {7,10}" -f $vm, $memText, $available, $maxVMs, $priceText, $spotPriceText, $priceMonth, $spotPriceMonth) -ForegroundColor Green
            } else {
                Write-Host ("  {0,-28} Memory: {1,-8} vCPUs: {2,5} -> Max VMs: {3,6}  $/hr (USD): {4}  $/mo (USD): {6,10}  Spot/hr (USD): {5}  Spot/mo (USD): {7,10}" -f $vm, $memText, $available, $maxVMs, $priceText, $spotPriceText, $priceMonth, $spotPriceMonth) -ForegroundColor Red
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

# Print disclaimer again at end
Write-Host "`nDISCLAIMER: This script is for informational purposes only and is NOT the official Azure Spot Advisor." -ForegroundColor Yellow
Write-Host "For official guidance on Spot VMs, eviction policies and recommended configurations, see: https://azure.microsoft.com/en-us/pricing/spot-advisor/" -ForegroundColor Yellow