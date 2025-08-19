
# Define regions and VM sizes
Write-Host "Checking US, Canada, and Australia regions..." -ForegroundColor Green
$regions = @(
    # US Regions
    "eastus", "eastus2", "westus", "westus2", "westus3", "centralus", "northcentralus", "southcentralus", "westcentralus",
    # Canada Regions  
    "canadacentral", "canadaeast",
    # Australia Regions
    "australiaeast", "australiasoutheast", "australiacentral", "australiacentral2"
)
$vmSizes = @{
    "Standard_D4s_v5"     = 4
    "Standard_HB120rs_v3" = 120
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

    foreach ($vm in $vmSizes.Keys) {
        $vcpuPerVM = $vmSizes[$vm]

        # Determine which quota name to look for
        if ($vm -like "Standard_HB*") {
            $quotaName = "standardHBv3Family"
        } elseif ($vm -like "Standard_D4s_v3*") {
            $quotaName = "standardDSv3Family"
        } elseif ($vm -like "Standard_D8as_v5*") {
            $quotaName = "standardDASv5Family"
        } else {
            $quotaName = "standardDFamily"
        }

        # Find the quota entry
        $quota = $usage | Where-Object { $_.Name -eq $quotaName }

        if ($quota) {
            $available = $quota.Limit - $quota.Current
            $maxVMs = [math]::Floor($available / $vcpuPerVM)
            if ($maxVMs -gt 0) {
                Write-Host "  $vm → Available vCPUs: $available → Max VMs: $maxVMs" -ForegroundColor Green
            } else {
                Write-Host "  $vm → Available vCPUs: $available → Max VMs: $maxVMs" -ForegroundColor Red
            }
        } else {
            Write-Host "  $vm → Quota info not found" -ForegroundColor Gray
        }
    }
    } catch {
        Write-Host "  Error checking region $region`: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "`n" + "="*80 -ForegroundColor Cyan
Write-Host "SUMMARY: Regions with available HB120rs_v3 quota:" -ForegroundColor Yellow
Write-Host "="*80 -ForegroundColor Cyan

# Find and display regions with HB120rs_v3 availability
$regionsWithHB = @()
foreach ($region in $regions) {
    $usage = az vm list-usage --location $region --query "[].{Name:name.value, Current:currentValue, Limit:limit}" --output json 2>$null | ConvertFrom-Json
    if ($usage) {
        $quota = $usage | Where-Object { $_.Name -eq "standardHBv3Family" }
        if ($quota) {
            $available = $quota.Limit - $quota.Current
            $maxVMs = [math]::Floor($available / 120)
            if ($maxVMs -gt 0) {
                $regionsWithHB += "$region`: $maxVMs HB120rs_v3 VMs available ($available vCPUs)"
            }
        }
    }
}

if ($regionsWithHB.Count -gt 0) {
    $regionsWithHB | ForEach-Object { Write-Host "  [OK] $_" -ForegroundColor Green }
} else {
    Write-Host "  [NONE] No regions found with available HB120rs_v3 quota" -ForegroundColor Red
}

Write-Host "`nRECOMMENDATION:" -ForegroundColor Yellow
if ($regionsWithHB.Count -gt 0) {
    Write-Host "  Best regions for HPC deployment with InfiniBand:" -ForegroundColor Green
    $regionsWithHB | ForEach-Object { 
        $region = $_.Split(':')[0]
        Write-Host "     -> $region" -ForegroundColor Cyan
    }
} else {
    Write-Host "  Request quota increase for HBv3 family in your preferred region" -ForegroundColor Yellow
    Write-Host "  Alternative: Use Standard_D8as_v5 for compute nodes (available in all regions)" -ForegroundColor Cyan
}