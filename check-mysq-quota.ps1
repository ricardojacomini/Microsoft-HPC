

# USAGE:
#   .\check-mysq-quota.ps1
#     - Checks default regions (US, Canada, Australia)
#   .\check-mysq-quota.ps1 -Regions @('eastus','westeurope','japaneast')
#     - Checks only specified regions
#   .\check-mysq-quota.ps1 -Regions @()
#     - Checks all Azure regions
#   .\check-mysq-quota.ps1 -Regions $null
#     - Checks all Azure regions

param(
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

# Use provided regions or get all if explicitly set to $null or empty
if ($null -eq $Regions -or $Regions.Count -eq 0) {
    $regions = az account list-locations --query "[].name" -o tsv
} else {
    $regions = $Regions
}

# Initialize counter and list
$availableCount = 0
$availableRegions = @()

# Loop through each region
foreach ($region in $regions) {
    Write-Host "Checking SKUs in region: $region"
    
    # Suppress warning by redirecting stderr to $null
    $skus = az mysql flexible-server list-skus --location $region -o table 2>$null
    
    if ($skus) {
        $availableCount++
        $availableRegions += $region
    }
}

# Display results
Write-Host "`nRegions with available MySQL Flexible Server SKUs:"
$availableRegions | ForEach-Object { Write-Host "- $_" }

Write-Host "`nTotal regions with available SKUs: $availableCount"

Write-Host "`nTo check SKUs in a specific region, run: az mysql flexible-server list-skus --location <region> -o table"
Write-Host "Replace <region> with the desired Azure region name."