# AMLFS Zone Availability Testing Script - Managed Identity Version
param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroup,
    [string]$TemplateFile = "infra-managed-identity.bicep",
    [string]$Location = "eastus"
)

function Test-AMLFSZoneAvailability {
    param(
        [string]$ResourceGroup,
        [string]$TemplateFile = "infra-managed-identity.bicep",
        [string]$Location = "eastus"
    )
    
    Write-Host "=== AMLFS Zone Availability Testing (Managed Identity) ===" -ForegroundColor Green
    Write-Host "Resource Group: $ResourceGroup" -ForegroundColor Cyan
    Write-Host "Template File: $TemplateFile" -ForegroundColor Cyan
    Write-Host "Location: $Location" -ForegroundColor Cyan
    Write-Host ""
    
    if (-not (Test-Path $TemplateFile)) {
        Write-Host "ERROR: Template file '$TemplateFile' not found!" -ForegroundColor Red
        return $null
    }
    
    $zones = @(1, 2, 3)
    $results = @{}
    
    foreach ($zone in $zones) {
        Write-Host "Testing Zone $zone..." -ForegroundColor Yellow
        
        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        try {
            $result = az deployment group validate --resource-group $ResourceGroup --template-file $TemplateFile --parameters "availabilityZone=$zone" "fsname=test-z$zone-$timestamp" --query "properties.provisioningState" -o tsv
            $result = $result.Trim()  # Remove any whitespace
            $results[$zone] = $result
            
            if ($result -eq "Succeeded") {
                Write-Host "  Zone $zone : AVAILABLE" -ForegroundColor Green
            } else {
                Write-Host "  Zone $zone : FAILED" -ForegroundColor Red
            }
        }
        catch {
            Write-Host "  Zone $zone : ERROR" -ForegroundColor Red
            $results[$zone] = "Error"
        }
    }
    
    Write-Host ""
    $availableZones = $results.Keys | Where-Object { $results[$_] -eq "Succeeded" } | Sort-Object
    
    if ($availableZones.Count -gt 0) {
        Write-Host "Available zones: $($availableZones -join ', ')" -ForegroundColor Green
        Write-Host "Recommended: Zone $($availableZones[0])" -ForegroundColor Yellow
        
        return @{
            AvailableZones = $availableZones
            RecommendedZone = $availableZones[0]
            Results = $results
        }
    } else {
        Write-Host "No zones available!" -ForegroundColor Red
        return $null
    }
}

# Main execution
Write-Host "Starting zone availability test (Managed Identity version)..." -ForegroundColor Cyan
$result = Test-AMLFSZoneAvailability -ResourceGroup $ResourceGroup -TemplateFile $TemplateFile -Location $Location

if ($null -ne $result) {
    Write-Host ""
    Write-Host "SUCCESS! Zone testing complete." -ForegroundColor Green
    Write-Host "Recommended deployment command:" -ForegroundColor Cyan
    Write-Host "az deployment group create --resource-group '$ResourceGroup' --template-file '$TemplateFile' --parameters 'availabilityZone=$($result.RecommendedZone)' --name 'deploy-$(Get-Date -Format "yyyyMMdd-HHmmss")'" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Note: This template includes managed identity and HSM configuration." -ForegroundColor Yellow
    Write-Host "The managed identity will be granted Storage Blob Data Contributor permissions automatically." -ForegroundColor Yellow
}
