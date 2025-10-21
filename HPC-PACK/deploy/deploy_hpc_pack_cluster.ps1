<#
.SYNOPSIS
    Deploys an HPC Pack cluster with a single head node for Windows workloads, including automated creation of a new Active Directory Domain.

.DESCRIPTION
    This PowerShell script automates the end-to-end deployment of an HPC Pack cluster in Azure, optimized for Windows-based high-performance computing scenarios. Key features include:
    - Automated provisioning of a resource group and all required Azure resources
    - Deployment of a single-head-node cluster with customizable VM sizes and OS images
    - Creation and configuration of a new Active Directory domain for the cluster
    - Secure credential handling and optional authentication key override
    - Optional integration with Azure Key Vault for secrets management
    - Modular functions for resource group management, subscription selection, and deployment
    - Clear validation and error handling, with guidance on expected ARM template warnings

.AUTHOR
    Ricardo de Souza Jacomini
    Microsoft Azure HPC + AI

.DATE
    June 23, 2025

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass .\deploy_hpc_pack_cluster.ps1"

.EXAMPLE
    # Keyless mode WITH staging container user delegation SAS (read/list) generation
    # SAS will only be generated when BOTH -StorageAuthMode Keyless and -GenerateStagingSas are specified.
    powershell -NoProfile -ExecutionPolicy Bypass  .\deploy_hpc_pack_cluster.ps1 -StorageAuthMode Keyless -GenerateStagingSas -StagingSasHours 4"

.EXAMPLE
    # Default run (uses deterministic staging storage account hpckvstage<region><timestamp>, e.g. hpckvstageeastus101411)
    # Where <timestamp> = MMddHH matching the resource group suffix (fixedSegment removed by design to shorten name).
    powershell -NoProfile -ExecutionPolicy Bypass  .\deploy_hpc_pack_cluster.ps1"

.EXAMPLE
    # Reuse existing resource group and specify a deterministic staging storage account name
    powershell -NoProfile -ExecutionPolicy Bypass  .\deploy_hpc_pack_cluster.ps1 -ResourceGroupName HPC-PACK-Jacomini-101317 -StagingStorageAccountName storageaccount20502460"

.EXAMPLE
    # Launch with the interactive numeric menu for post-deployment actions
    powershell -NoProfile -ExecutionPolicy Bypass  .\deploy_hpc_pack_cluster.ps1 -UseMenu

.EXAMPLE
    # Skip menu and directly enable temporary public network access for 90 seconds then revert
    powershell -NoProfile -ExecutionPolicy Bypass  .\deploy_hpc_pack_cluster.ps1 -NextAction "Enable public network" -TemporaryPublicNetworkSeconds 90

.EXAMPLE
    # Use short code alias to choose the private endpoint guidance path
    powershell -NoProfile -ExecutionPolicy Bypass  .\deploy_hpc_pack_cluster.ps1 -NextActionCode PrivateEndpoint

.EXAMPLE
    # Automatically attempt certificate repair AND then show policy exemption guidance
    powershell -NoProfile -ExecutionPolicy Bypass  .\deploy_hpc_pack_cluster.ps1 -AutoRepairNewCert -NextActionCode PolicyExemption

.EXAMPLE
    # Create a private endpoint automatically (no prompt) after deployment
    powershell -NoProfile -ExecutionPolicy Bypass  .\deploy_hpc_pack_cluster.ps1 -NextActionCode PrivateEndpoint -CreatePrivateEndpoint -PrivateEndpointVnetName MyVnet -PrivateEndpointSubnetName KvSubnet -PrivateEndpointName kv-pe01

.PARAMETER UseMenu
    Displays an interactive numbered menu for selecting the post-deployment next step when neither -NextAction nor -NextActionCode is supplied.

.PARAMETER NextAction
    Full descriptive string for the post-deployment path. Mutually overridable by -NextActionCode (the short code wins if both provided).

.PARAMETER NextActionCode
    Short code alias: EnablePna | PrivateEndpoint | PolicyExemption | Other. Overrides -NextAction if both are given.

.PARAMETER TemporaryPublicNetworkSeconds
    When enabling public network (-NextAction/Code selects EnablePna), automatically re-disables public access after the specified number of seconds (>0).

.NOTES
    Selection Precedence:
      1. If -NextActionCode is specified it overrides -NextAction.
      2. If neither is specified and -UseMenu is passed, an interactive menu appears.
      3. If neither is specified and -UseMenu is NOT passed, a free-text prompt appears (legacy behavior).
    The menu options map as follows:
      1 => Enable public network
      2 => Keep PNA disabled; guide me through private endpoint option
      3 => Focus on policy exemption so deployment script (newCert) succeeds
      4 => Something else (describe)

.NOTES
    - Validation warnings such as "A nested deployment got short-circuited and all its resources got skipped from validation" are expected when using Test-AzResourceGroupDeployment with complex ARM templates. These do not indicate deployment failure.
    - For production use, review and update parameters such as VM sizes, admin credentials, and domain names as appropriate for your environment.
    - Monitor deployment progress and status in the Azure Portal under Resource Group > Deployments.

.LINK
    https://aka.ms/hpcgit
    https://github.com/Azure/hpcpack-template/tree/master
    https://github.com/Azure/hpcpack-template/blob/master/GeneratedTemplates/new-1hn-wincn-ad.json
#
# Recommended run examples
#
# Default / interactive (from the `deploy` folder):
#   This will: create MI, create storage account (Keyless when requested), attempt role assignment to `hpcpack-mi`,
#   generate a user-delegation SAS (requires your login to have RBAC), run deployment, and run AutoRepairNewCert if needed.
#   It will skip private endpoint creation unless explicitly requested.
#
#   powershell.exe -NoProfile -ExecutionPolicy Unrestricted -File .\deploy_hpc_pack_cluster.ps1
#
# Keyless (generate user-delegation SAS) + AutoRepair (recommended if subscription policy blocks account keys):
#
#   powershell.exe -NoProfile -ExecutionPolicy Unrestricted -File .\deploy_hpc_pack_cluster.ps1 -StorageAuthMode Keyless -GenerateStagingSas -AutoRepairNewCert
#
# Optional: run and create private endpoint automatically (only if VNet/subnet already exist and you want non-interactive)
#  (provide private endpoint flags; these names are examples and should match your environment):
#
#   powershell.exe -NoProfile -ExecutionPolicy Unrestricted -File .\deploy_hpc_pack_cluster.ps1 -StorageAuthMode Keyless -GenerateStagingSas -AutoRepairNewCert -NextActionCode PrivateEndpoint -CreatePrivateEndpoint -PrivateEndpointVnetName 'hpcpackvnet' -PrivateEndpointSubnetName 'Subnet-1' -PrivateEndpointName 'hpcpack-kv-pe' -PrivateDnsZoneResourceGroup 'HPC-PACK-Jacomini-102012' -PrivateDnsZoneName 'privatelink.vaultcore.azure.net'
#
#>

param(
    [ValidateSet('KeyVault','Keyless')]
    [string]$StorageAuthMode = 'KeyVault',
    [string]$KeyVaultName,
    [string]$KeyVaultResourceGroup,
    [switch]$ForceNewResourceGroup,
    [switch]$GenerateStagingSas,
    [int]$StagingSasHours = 24,
    [string]$StagingStorageAccountName,
    [string]$ResourceGroupName,
    [switch]$EnableCustomRole,
    [switch]$ForceProceedWithServiceManaged,
    [switch]$AutoRepairNewCert,
    # Post-deployment decision helper pre-selection
    [ValidateSet('Enable public network','Keep PNA disabled; guide me through private endpoint option','Focus on policy exemption so deployment script (newCert) succeeds','Something else (describe)')]
    [string]$NextAction,
    # Simpler code aliases for NextAction (optional)
    [ValidateSet('EnablePna','PrivateEndpoint','PolicyExemption','Other')]
    [string]$NextActionCode,
    # Enable interactive numeric menu for NextAction selection if not supplied
    [switch]$UseMenu,
    # Auto-disable public network after enabling (seconds > 0 triggers revert)
    [int]$TemporaryPublicNetworkSeconds = 0,
    # Private endpoint automation parameters
    [switch]$CreatePrivateEndpoint,
    [string]$PrivateEndpointVnetName,
    [string]$PrivateEndpointSubnetName,
    [string]$PrivateEndpointName,
    [string]$PrivateDnsZoneResourceGroup,
    [string]$PrivateDnsZoneName = 'privatelink.vaultcore.azure.net'
)

function Select-AzSubscriptionContext {
    try {
        # Try GUI selection first (works in interactive desktop sessions)
        $selectedSub = Get-AzSubscription | Out-GridView -Title "Select a subscription" -PassThru
        if ($selectedSub) {
            Set-AzContext -SubscriptionId $selectedSub.Id -TenantId $selectedSub.TenantId
            return $selectedSub
        }
    }
    catch {
        # Out-GridView or GUI not available, fall back to text-based selection
        Write-Host "ℹ️ GUI selection unavailable or canceled; falling back to text selection..." -ForegroundColor Yellow
    }

    # Text-based fallback (non-interactive friendly)
    $subs = Get-AzSubscription -ErrorAction SilentlyContinue
    if (-not $subs -or $subs.Count -eq 0) {
        Write-Host "`n❌ No subscriptions available. Run: Connect-AzAccount" -ForegroundColor Red
        exit 1
    }
    if ($subs.Count -eq 1) {
        $fallback = $subs[0]
        Write-Host "ℹ️ Using only available subscription: $($fallback.Name) ($($fallback.Id))"
        Set-AzContext -SubscriptionId $fallback.Id -TenantId $fallback.TenantId
        return $fallback
    }

    # Present a simple numbered list for selection in text-mode
    for ($i = 0; $i -lt $subs.Count; $i++) { Write-Host "[$($i+1)] $($subs[$i].Name) ($($subs[$i].Id))" }
    $choice = Read-Host "Enter subscription number (1-$($subs.Count)) [default 1]"
    if ([string]::IsNullOrWhiteSpace($choice)) { $choice = 1 }
    if ($choice -as [int] -and $choice -ge 1 -and $choice -le $subs.Count) {
        $sel = $subs[$choice - 1]
        Set-AzContext -SubscriptionId $sel.Id -TenantId $sel.TenantId
        return $sel
    }
    Write-Host "❌ Invalid selection. Exiting." -ForegroundColor Red
    exit 1
}

function Select-AzSubscriptionContext-text {
    # Try to get current context first
    $currentContext = Get-AzContext
    if ($currentContext -and $currentContext.Subscription) {
        Write-Host "🔍 Using current Azure context:"
        Write-Host "   Subscription: $($currentContext.Subscription.Name) ($($currentContext.Subscription.Id))"
        Write-Host "   Account: $($currentContext.Account.Id)"
        
        $confirmation = Read-Host "Continue with this subscription? (Y/N)"
        if ($confirmation -eq "Y" -or $confirmation -eq "y") {
            return $currentContext.Subscription
        }
    }
    
    # Fallback: Try Get-AzSubscription with error handling
    try {
        $selectedSub = Get-AzSubscription | Out-GridView -Title "Select a subscription" -PassThru
        if (-not $selectedSub) {
            Write-Host "`n❌ No subscription selected. Exiting script."
            Write-Host "Try running: Connect-AzAccount "
            exit 1
        }
        Set-AzContext -SubscriptionId $selectedSub.Id -TenantId $selectedSub.TenantId
        return $selectedSub
    }
    catch {
        Write-Host "❌ Error accessing subscriptions via GUI selection: $($_.Exception.Message)"
        Write-Host "Attempting non-interactive fallback..."
        try {
            $subs = Get-AzSubscription -ErrorAction Stop
            if ($subs -and $subs.Count -gt 0) {
                $fallback = $subs[0]
                Write-Host "ℹ️  Falling back to first available subscription: $($fallback.Name) ($($fallback.Id))"
                Set-AzContext -SubscriptionId $fallback.Id -TenantId $fallback.TenantId
                return $fallback
            } else {
                Write-Host "❌ No subscriptions available. Run: Connect-AzAccount"
                exit 1
            }
        }
        catch {
            Write-Host "❌ Still unable to get subscriptions. Run: Connect-AzAccount"
            Write-Host "Or: Update-Module Az -Force"
            exit 1
        }
    }
}

function Invoke-EnsureResourceGroup {
    param (
        [string]$Name,
        [string]$Location
    )
    if (Get-AzResourceGroup -Name $Name -ErrorAction SilentlyContinue) {
        if ($ForceNewResourceGroup) {
            Write-Host "🗑️  ForceNewResourceGroup specified. Removing existing resource group '$Name'..."
            Remove-AzResourceGroup -Name $Name -Force -AsJob | Out-Null
            Write-Host "⏳ Waiting for resource group deletion to complete..."
            while (Get-AzResourceGroup -Name $Name -ErrorAction SilentlyContinue) { Start-Sleep -Seconds 5 }
            Write-Host "✅ Previous resource group removed. Creating fresh resource group..."
            New-AzResourceGroup -Name $Name -Location $Location | Out-Null
        } else {
            Write-Host "Resource group '$Name' exists. (Use -ForceNewResourceGroup to recreate automatically.)"
        }
    } else {
        Write-Host "📦 Creating resource group '$Name'..."
        New-AzResourceGroup -Name $Name -Location $Location | Out-Null
        Write-Host "✅ Resource group '$Name' created."
    }
}

function Get-AuthenticationKey {
    param ([string]$SubscriptionId)
    $authInput = Read-Host -Prompt "Enter authentication key (press Enter to use 'subscriptionId: $SubscriptionId')"
    if ([string]::IsNullOrWhiteSpace($authInput)) {
        Write-Host "Using default authentication key: subscriptionId: $SubscriptionId"
        return "subscriptionId: $SubscriptionId"
    }
    return $authInput
}

# Ensures a user-assigned managed identity exists (needed for script staging & optional template MI usage)
function Invoke-EnsureManagedIdentity {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$ResourceGroup,
        [Parameter(Mandatory)][string]$Location
    )
    Write-Host "\n🆔 Ensuring managed identity '$Name' in resource group '$ResourceGroup'..."
    $mi = az identity show --name $Name --resource-group $ResourceGroup -o json 2>$null | ConvertFrom-Json
    if (-not $mi) {
        Write-Host "   Creating managed identity '$Name'..."
        $raw = az identity create --name $Name --resource-group $ResourceGroup --location $Location -o json 2>&1
        if ($LASTEXITCODE -ne 0) { Write-Host "❌ Failed to create managed identity: $raw"; return $null }
        try { $created = $raw | ConvertFrom-Json } catch { Write-Host "❌ Unable to parse identity create output: $raw"; return $null }
        if (-not $created.id) { Write-Host "❌ Managed identity creation returned no id."; return $null }
        Write-Host "   ✅ Managed identity created: $($created.id)"
        return $created.id
    } else {
        Write-Host "   ℹ️  Managed identity already exists: $($mi.id)"
        return $mi.id
    }
}

# Optionally create a custom role from role.json if present and not already defined
function Invoke-EnsureCustomRoleFromFile {
    param(
        [Parameter(Mandatory)][string]$RoleName,
        [Parameter(Mandatory)][string]$SubscriptionId
    )
    $roleFile = Join-Path -Path (Get-Location) -ChildPath 'role.json'
    if (-not (Test-Path $roleFile)) { return }
    Write-Host "\n🧩 role.json detected. Ensuring custom role '$RoleName' exists..."
    $exists = az role definition list --custom-role-only true --query "[?roleName=='$RoleName'] | [0].roleName" -o tsv 2>$null
    if ($exists) { Write-Host "   ℹ️  Custom role already exists."; return }
    $temp = New-TemporaryFile
    try {
        # Perform placeholder substitutions similar to sed usage in bash script
        $content = Get-Content $roleFile -Raw
        $content = $content -replace '/subscriptions/\$SBC', "/subscriptions/$SubscriptionId"
        $content = $content -replace '\$ROLE', $RoleName
        # $NAME not essential here; substitute with role name if present
        $content = $content -replace '\$NAME', $RoleName
        Set-Content -Path $temp -Value $content -Encoding utf8
        $create = az role definition create --role-definition $temp 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "   ❌ Failed to create custom role: $create"
        } else {
            Write-Host "   ✅ Custom role '$RoleName' created."
        }
    } finally {
        if (Test-Path $temp) { Remove-Item $temp -Force }
    }
}

function Grant-KeyVaultAdminAccess {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName
    )

    try {
        # Locate Key Vault created in the resource group (best-effort)
        $keyVault = Get-AzKeyVault -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $keyVault) {
            Write-Host "⚠️  No Key Vault found in resource group '$ResourceGroupName'. Will not attempt role assignment now." -ForegroundColor Yellow
            return $false
        }
        $scope = $keyVault.ResourceId

        # Resolve signed-in user's object id more robustly
        $currentUpn = (Get-AzContext).Account.Id
        $adUser = $null
        if ($currentUpn) {
            $adUser = Get-AzADUser -UserPrincipalName $currentUpn -ErrorAction SilentlyContinue
        }
        if (-not $adUser) {
            # Fallback to SignedIn (older Az versions)
            $adUser = Get-AzADUser -SignedIn -ErrorAction SilentlyContinue
        }
        if (-not $adUser -or -not $adUser.Id) {
            Write-Host "⚠️  Could not determine signed-in user's object id. Skipping Key Vault role assignment. You may assign 'Key Vault Administrator' to your user at scope $scope manually." -ForegroundColor Yellow
            return $false
        }
        $objectId = $adUser.Id

        Write-Host "🔐 Assigning 'Key Vault Administrator' role to the signed-in user (objectId: $objectId)..."
        New-AzRoleAssignment -ObjectId $objectId -RoleDefinitionName "Key Vault Administrator" -Scope $scope -ErrorAction Stop
        Write-Host "✅ Role assignment successful for Key Vault: $($keyVault.VaultName)"
        return $true
    }
    catch {
        Write-Host "❌ Failed to assign Key Vault role: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Invoke-DeployHPCPackCluster {
    param (
        [string]$TemplateFile,
        [string]$ResourceGroup,
        [hashtable]$Parameters
    )
    try {
        Write-Host "🚀 Starting HPC Pack deployment..."
        Write-Host "`n⚠️  IMPORTANT: If you encounter Key Vault role assignment errors, you need:"
        Write-Host "   • User Access Administrator permissions on the subscription/resource group"
        Write-Host "   • Or ask your Azure admin to assign these permissions"
        
        # Validate template first
        Write-Host "`n� Validating ARM template..."

        # Build a filtered parameter set containing only parameters declared by the compiled template.
        # Prefer enumerating parameters via `bicep build --stdout`. If bicep is unavailable or the build fails,
        # fall back to removing known script-only keys from the parameter bag.
        $deployParameters = @{}
        try {
            Write-Host "ℹ️  Enumerating template parameters via Bicep..."
            $bicepCmd = 'bicep'
            $bicepArgs = @('build', $TemplateFile, '--stdout')
            $bicepOut = & $bicepCmd @bicepArgs 2>&1
            if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($bicepOut)) { throw "bicep build failed: $bicepOut" }
            $armTemplate = $bicepOut | ConvertFrom-Json -ErrorAction Stop
            $templateParamNames = @()
            if ($armTemplate.parameters) { $templateParamNames = $armTemplate.parameters.PSObject.Properties | ForEach-Object { $_.Name } }
            foreach ($pn in $templateParamNames) {
                if ($Parameters.ContainsKey($pn)) { $deployParameters[$pn] = $Parameters[$pn] }
            }
            Write-Host "ℹ️  Passing $(($deployParameters.Keys).Count) parameters to template: $((($deployParameters.Keys) -join ', '))"
        } catch {
            Write-Host "⚠️  Could not enumerate template parameters via Bicep: $($_.Exception.Message). Falling back to exclusion list." -ForegroundColor Yellow
            # Conservative fallback: copy parameters and then remove script-only keys
            $deployParameters = @{}
            foreach ($k in $Parameters.Keys) { $deployParameters[$k] = $Parameters[$k] }
            foreach ($rm in @('resourceGroupPrefix','stagingPrefix','storageAuthMode','location')) { if ($deployParameters.ContainsKey($rm)) { $deployParameters.Remove($rm) } }
            Write-Host "ℹ️  After fallback exclusion, passing $(($deployParameters.Keys).Count) parameters to template."
        }

    $validation = Test-AzResourceGroupDeployment -ResourceGroupName $ResourceGroup -TemplateFile $TemplateFile -TemplateParameterObject $deployParameters -ErrorAction SilentlyContinue
        
        if ($validation) {
            Write-Host "⚠️  Template validation found potential issues:"
            $validation | ForEach-Object { Write-Host "   • $($_.Message)" }
            Write-Host "ℹ️  Note: Some warnings about nested deployments are expected and don't indicate failure."
        } else {
            Write-Host "✅ Template validation passed."
        }
        
        Write-Host "`n📊 Starting deployment..."
        
    $deployment = New-AzResourceGroupDeployment -ResourceGroupName $ResourceGroup -TemplateFile $TemplateFile -TemplateParameterObject $deployParameters -Verbose
        
        if ($deployment.ProvisioningState -eq "Succeeded") {
            Write-Host "✅ Deployment completed successfully!"
            Write-Host "🌐 Check the Azure Portal for your HPC Pack cluster resources."
            return $true
        } else {
            Write-Host "❌ Deployment completed with issues. Check Azure Portal for details."
            Write-Host "📊 Deployment State: $($deployment.ProvisioningState)"
            return $false
        }
    } catch {
        Write-Host "❌ Deployment failed: $_"
        Write-Host "`n💡 Common solutions:"
        Write-Host "   1. Clean resource group: Remove and recreate the resource group"
        Write-Host "   2. Check permissions: Request User Access Administrator role"
        Write-Host "   3. Try different subscription: Use HPC-specific subscriptions"
        Write-Host "   4. Use unique resource group name: Avoid naming conflicts"
        return $false
    }
}

# Fixing unapproved verb by renaming the function to use an approved verb
function New-PolicyExemption {
    param (
        [Parameter(Mandatory = $true)]
        [string]$PolicyAssignmentName,
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName,
        [Parameter(Mandatory = $true)]
        [string]$ExemptionName
    )

    Write-Host "🔍 Checking if policy exemption '$ExemptionName' exists..."
    $exemptionExists = az policy exemption show --name $ExemptionName --resource-group $ResourceGroupName -o json 2>$null | ConvertFrom-Json

    if ($exemptionExists) {
        Write-Host "✅ Policy exemption '$ExemptionName' already exists. Skipping creation."
        return
    }

    Write-Host "🏗️ Creating policy exemption '$ExemptionName' for assignment '$PolicyAssignmentName'..."
    $result = az policy exemption create --name $ExemptionName --policy-assignment $PolicyAssignmentName --scope "/subscriptions/$((Get-AzContext).Subscription.Id)/resourceGroups/$ResourceGroupName" --exemption-category Waiver -o json 2>&1

    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Failed to create policy exemption: $result"
    } else {
        Write-Host "✅ Policy exemption '$ExemptionName' created successfully."
    }
}

# Example usage of the function
if ($NextActionCode -eq 'PolicyExemption') {
    $policyAssignmentName = "Deny-SharedKeyAccess"
    $exemptionName = "AllowSharedKeyAccessExemption"

   # New-PolicyExemption -PolicyAssignmentName $policyAssignmentName -ResourceGroupName $ResourceGroupName -ExemptionName $exemptionName
}

# Main Execution
# Resolve template path relative to script location to avoid CWD issues
# The deploy script lives under `deploy/`. Place or fetch a local `bicep/` folder next to this script
# (i.e., $PSScriptRoot\bicep) so templates are resolved from the script folder.
$TemplateFileAD = Join-Path $PSScriptRoot 'bicep\new-1hn-wincn-ad.bicep'

# Ensure Bicep files exist in the repository root. If the repo-level `bicep` folder is missing or empty, fetch
# the upstream Bicep folder from GitHub (https://github.com/Azure/hpcpack-template/tree/master/Bicep)
function Invoke-EnsureBicepFromGitHub {
    param(
        # Default destination: a 'bicep' folder next to this deploy script (script-local bicep folder)
        [string]$Destination = (Join-Path $PSScriptRoot 'bicep'),
        [string]$GithubZipUrl = 'https://github.com/Azure/hpcpack-template/archive/refs/heads/master.zip'
    )

    try {
        # If destination contains any .bicep files, assume it's populated
        if (Test-Path $Destination) {
            $existing = Get-ChildItem -Path $Destination -Filter '*.bicep' -Recurse -ErrorAction SilentlyContinue
            if ($existing -and $existing.Count -gt 0) { Write-Host "ℹ️  Local bicep files detected; skipping fetch."; return $true }
        }

        Write-Host "⬇️  Local bicep folder missing or empty. Downloading upstream Bicep files from GitHub..."
        $tmpZip = Join-Path $env:TEMP ("hpcpack_bicep_{0}.zip" -f ([Guid]::NewGuid().ToString()))
        Invoke-WebRequest -Uri $GithubZipUrl -OutFile $tmpZip -UseBasicParsing -TimeoutSec 180

        $extractDir = Join-Path $env:TEMP ("hpcpack_bicep_extract_{0}" -f ([Guid]::NewGuid().ToString()))
        New-Item -ItemType Directory -Path $extractDir | Out-Null

        # Try normal extraction first. On Windows the default temp path plus repo nested paths can exceed MAX_PATH
        # causing Expand-Archive/Zip extraction to fail. If that happens, retry extraction into a short-root path
        # (C:\hpcpack_bicep_extract_...) to avoid long-path issues.
        $usedExtractDir = $null
        try {
            Expand-Archive -Path $tmpZip -DestinationPath $extractDir -Force
            $usedExtractDir = $extractDir
        } catch {
            Write-Host "⚠️  Expand-Archive failed on default temp path: $($_.Exception.Message)"
            # Prepare a short-path fallback under C:\
            try {
                $shortRoot = 'C:\temp\hpcpack_bicep_extract'
                $shortExtractDir = Join-Path $shortRoot ([Guid]::NewGuid().ToString())
                if (-not (Test-Path $shortRoot)) { New-Item -ItemType Directory -Path $shortRoot | Out-Null }
                New-Item -ItemType Directory -Path $shortExtractDir | Out-Null
                Write-Host "⬇️  Retrying extraction to short path: $shortExtractDir"
                Expand-Archive -Path $tmpZip -DestinationPath $shortExtractDir -Force
                $usedExtractDir = $shortExtractDir
            } catch {
                Write-Host "❌ Expand-Archive also failed on short path: $($_.Exception.Message)" -ForegroundColor Red
                # Cleanup any partial dirs and rethrow to be handled by outer catch
                if (Test-Path $extractDir) { Remove-Item -Path $extractDir -Recurse -Force -ErrorAction SilentlyContinue }
                if ($shortExtractDir -and (Test-Path $shortExtractDir)) { Remove-Item -Path $shortExtractDir -Recurse -Force -ErrorAction SilentlyContinue }
                throw
            }
        }

        $sourceBicep = Join-Path $usedExtractDir 'hpcpack-template-master\Bicep'
        if (-not (Test-Path $sourceBicep)) {
            Write-Host "❌ Upstream archive did not contain a Bicep folder at expected path: $sourceBicep" -ForegroundColor Red
            Remove-Item -Path $tmpZip -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $extractDir -Recurse -Force -ErrorAction SilentlyContinue
            return $false
        }

    if (-not (Test-Path $Destination)) { New-Item -ItemType Directory -Path $Destination | Out-Null }
    Write-Host "📥 Copying Bicep files into: $Destination (existing files will be overwritten)"
    Copy-Item -Path (Join-Path $sourceBicep '*') -Destination $Destination -Recurse -Force

    # Cleanup: remove tmp zip and any extract dirs we created
    if (Test-Path $tmpZip) { Remove-Item -Path $tmpZip -Force -ErrorAction SilentlyContinue }
    if ($usedExtractDir -and (Test-Path $usedExtractDir)) { Remove-Item -Path $usedExtractDir -Recurse -Force -ErrorAction SilentlyContinue }
    if ($extractDir -and (Test-Path $extractDir) -and $extractDir -ne $usedExtractDir) { Remove-Item -Path $extractDir -Recurse -Force -ErrorAction SilentlyContinue }

    Write-Host "✅ Bicep files fetched and updated from upstream."
    return $true
    }
    catch {
        Write-Host "❌ Failed to fetch or extract upstream Bicep files: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Try to ensure bicep presence (this will be a no-op if files already exist)
if (-not (Invoke-EnsureBicepFromGitHub)) { Write-Host "⚠️ Proceeding but some bicep files may be missing." -ForegroundColor Yellow }

if (-not (Test-Path $TemplateFileAD)) {
    Write-Host "❌ Cannot locate template at $TemplateFileAD even after attempting to fetch upstream. Ensure repository structure intact or run the script again." -ForegroundColor Red
    exit 1
}

# Allow user to supply an existing resource group name via -ResourceGroupName, otherwise generate a timestamped name
# Default prefix for generated resource group names. This value is now expected to be provided via
# the external parameters file (`hpc-pack-parameters.json`) under 'resourceGroupPrefix'. If not present,
# fall back to a sensible default below.
# Compute timestamp early; we'll generate the resource group name after merging parameters so
# that 'resourceGroupPrefix' from the JSON file can control the RG name fully.
$timestamp = Get-Date -Format "MMddHH"
if (-not [string]::IsNullOrWhiteSpace($ResourceGroupName)) {
    $resourceGroup = $ResourceGroupName
    Write-Host "ℹ️  Using provided resource group name: $resourceGroup"
} else {
    # Will be computed after parameters are merged (uses resourceGroupPrefix from JSON if present)
    $resourceGroup = $null
}

# Password handling: allow non-interactive via HPC_ADMIN_PASSWORD env var
$plainAdminPassword = $env:HPC_ADMIN_PASSWORD
if ([string]::IsNullOrWhiteSpace($plainAdminPassword)) {
    $adminPassword = Read-Host -Prompt "Enter admin password" -AsSecureString
    $plainAdminPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($adminPassword))
} else {
    Write-Host "🔐 Using admin password from HPC_ADMIN_PASSWORD environment variable (non-interactive)."
}

# Basic complexity sanity check (not exhaustive)
if ($plainAdminPassword.Length -lt 12 -or ($plainAdminPassword -cmatch '^[a-zA-Z0-9]*$')) {
    Write-Host "⚠️  Provided password may not meet complexity requirements (length >=12 & mixed chars recommended)."
}

$selectedSub = Select-AzSubscriptionContext
$subscriptionId = $selectedSub.Id
$authenticationKey = Get-AuthenticationKey -SubscriptionId $subscriptionId

# Determine (or honor provided) staging storage account name (24 char limit, lowercase)
# New default: deterministic dedicated exempt staging account for KeyVault deployment script staging.
# NOTE: Ensure $location is set from parameters (see below)
# Defer staging storage account name computation until after parameters are merged so
# stagingPrefix can be supplied via hpc-pack-parameters.json. $saName will be set later.

# Configuration (only parameters actually present in the Bicep template should be included)
$parameters = @{
    adminPassword = $plainAdminPassword
    # Pass plain string for secureString template parameter to avoid serialization error
    authenticationKey = $authenticationKey
    storageAuthMode = $StorageAuthMode
}

# If a local JSON parameters file exists, merge its values into $parameters
$paramFile = Join-Path -Path $PSScriptRoot -ChildPath 'hpc-pack-parameters.json'
if (Test-Path $paramFile) {
    Write-Host "ℹ️  Loading parameter overrides from $paramFile"
    try {
        $json = Get-Content -Path $paramFile -Raw | ConvertFrom-Json
        foreach ($prop in $json.PSObject.Properties) {
            $k = $prop.Name
            $v = $prop.Value
            if ($parameters.ContainsKey($k)) {
                Write-Host "   • Overriding parameter: $k => $v"
                $parameters[$k] = $v
            } else {
                Write-Host "   • Adding custom parameter: $k => $v"
                $parameters[$k] = $v
            }
        }
    } catch {
        Write-Host "⚠️ Failed to read or parse $($paramFile): $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# After merging parameters, populate script-local variables from the centralized $parameters
try {
    if ($parameters.ContainsKey('location')) { $location = [string]$parameters['location'] }
    if ($parameters.ContainsKey('clusterName')) { $clusterName = [string]$parameters['clusterName'] }
    if ($parameters.ContainsKey('domainName')) { $domainName = [string]$parameters['domainName'] }
    if ($parameters.ContainsKey('adminUsername')) { $adminUsername = [string]$parameters['adminUsername'] }
    if ($parameters.ContainsKey('adminPassword') -and -not [string]::IsNullOrWhiteSpace([string]$parameters['adminPassword'])) { $plainAdminPassword = [string]$parameters['adminPassword']; $parameters['adminPassword'] = $plainAdminPassword }
} catch {
    Write-Host "⚠️ Failed to populate script-local variables from parameters: $($_.Exception.Message)" -ForegroundColor Yellow
}

# Compute resource group now that parameters are merged and resourceGroupPrefix may have been supplied.
try {
    if ([string]::IsNullOrWhiteSpace($resourceGroup)) {
        # Require resourceGroupPrefix to be supplied via hpc-pack-parameters.json. Fail fast if missing.
        if ($parameters.ContainsKey('resourceGroupPrefix') -and -not [string]::IsNullOrWhiteSpace([string]$parameters['resourceGroupPrefix'])) {
            $resourceGroupPrefix = [string]$parameters['resourceGroupPrefix']
            $resourceGroup = "$resourceGroupPrefix-$timestamp"
            Write-Host "ℹ️  Computed resource group name from parameters: $resourceGroup"
        } else {
            Write-Host "❌ Missing required parameter 'resourceGroupPrefix' in hpc-pack-parameters.json. Please add it and re-run." -ForegroundColor Red
            exit 2
        }
    }
} catch {
    Write-Host "⚠️ Failed while computing resource group name: $($_.Exception.Message)" -ForegroundColor Yellow
}

# Compute staging storage account name now that location and stagingPrefix may be available in parameters
if ([string]::IsNullOrWhiteSpace($StagingStorageAccountName)) {
    $regionToken = ($location -replace '\s','').ToLower()
    $ts = $timestamp
    $maxLen = 24
    # stagingPrefix must come from the external parameters file (hpc-pack-parameters.json).
    if ($parameters.ContainsKey('stagingPrefix') -and -not [string]::IsNullOrWhiteSpace([string]$parameters['stagingPrefix'])) {
        $stagingPrefix = [string]$parameters['stagingPrefix']
    } else {
        Write-Host "❌ Missing required parameter 'stagingPrefix' in hpc-pack-parameters.json. Please add it and re-run." -ForegroundColor Red
        exit 2
    }
    $remainingForRegion = $maxLen - ($stagingPrefix.Length + $ts.Length)
    if ($remainingForRegion -lt 1) { $remainingForRegion = 1 }
    $regionPart = if ($regionToken.Length -le $remainingForRegion) { $regionToken } else { $regionToken.Substring(0, $remainingForRegion) }
    $StagingStorageAccountName = ($stagingPrefix + $regionPart + $ts).ToLower()
    Write-Host "ℹ️  Using default dedicated staging storage account name: $StagingStorageAccountName"
} else {
    if ($StagingStorageAccountName.Length -gt 24) { $StagingStorageAccountName = $StagingStorageAccountName.Substring(0,24) }
    $StagingStorageAccountName = $StagingStorageAccountName.ToLower()
}
$saName = $StagingStorageAccountName

# If the parameters file supplies a resourceGroupPrefix, allow it to override the script default
# and recompute the generated resource group name when the user did not supply -ResourceGroupName.
try {
    if ($parameters.ContainsKey('resourceGroupPrefix')) {
        $rgPrefixCandidate = [string]$parameters['resourceGroupPrefix']
        if (-not [string]::IsNullOrWhiteSpace($rgPrefixCandidate)) {
            Write-Host "ℹ️  Overriding resourceGroupPrefix from params file: $rgPrefixCandidate"
            $resourceGroupPrefix = $rgPrefixCandidate
            if ([string]::IsNullOrWhiteSpace($ResourceGroupName)) {
                # Recompute deterministic RG name using same timestamp
                $timestamp = Get-Date -Format "MMddHH"
                $resourceGroup = "$resourceGroupPrefix-$timestamp"
                Write-Host "ℹ️  Computed resource group name: $resourceGroup"
            } else {
                Write-Host "ℹ️  -ResourceGroupName supplied; will not override explicit resource group: $resourceGroup"
            }
        }
    }
} catch {
    Write-Host "⚠️ Failed while applying resourceGroupPrefix override: $_" -ForegroundColor Yellow
}

function New-StagingStorageAccount {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$ResourceGroup,
        [Parameter(Mandatory)][string]$Location,
        [string]$IdentityName = 'hpcpack-mi',
        [string]$RoleName = 'Storage Blob Data Contributor',
        [string]$StorageAuthMode = 'KeyVault'
    )
  Write-Host "\n🗂️  Ensuring staging storage account '$Name' in resource group '$ResourceGroup'..."
    $existingJson = az storage account show --name $Name --resource-group $ResourceGroup -o json 2>$null
    if ($LASTEXITCODE -eq 0 -and $existingJson) {
        try { $existingObj = $existingJson | ConvertFrom-Json } catch { $existingObj = $null }
        if ($existingObj -and $existingObj.id) {
            Write-Host "ℹ️  Storage account already exists: $($existingObj.id)"
            return $existingObj.id
        }
        }

    $COMMON_TAGS = @{
        owner = $NAME
        purpose = "storage-network-identity"
        createdBy = "az-create-storage-account"
        createdAt = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
    }

    # Build base create arguments; allow-shared-key-access depends on StorageAuthMode
    $allowShared = if ($StorageAuthMode -eq 'Keyless') { 'false' } else { 'true' }
    $createArgs = @(
        'storage','account','create',
        '--name', $Name,
        '--resource-group', $ResourceGroup,
        '--location', $Location,
        '--sku','Standard_LRS',
        '--kind','StorageV2',
        '--https-only','true',
        '--allow-shared-key-access', $allowShared,
        '--tags', ($COMMON_TAGS -join ';'),
        '-o','json'
    )

    $rawCreate = az @createArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Failed to create storage account: $rawCreate"; exit 1
    }
    try { $saObj = $rawCreate | ConvertFrom-Json } catch { Write-Host "❌ Could not parse storage account creation output: $rawCreate"; exit 1 }
    if (-not $saObj.id) { Write-Host "❌ Storage account JSON missing id."; exit 1 }
    $saId = $saObj.id


    Write-Host "✅ Created storage account: $saId"

    # Ensure the allow-shared-key-access property is explicitly applied (update in case API default differed)
    try {
        $updateOut = az storage account update --ids $saId --allow-shared-key-access $allowShared -o none 2>&1
        if ($LASTEXITCODE -eq 0) { Write-Host "✅ Storage account allow-shared-key-access set to $allowShared." } else { Write-Host "⚠️ Could not set allow-shared-key-access explicitly: $updateOut" -ForegroundColor Yellow }
    } catch {
        Write-Host "⚠️ Exception while updating storage account allow-shared-key-access: $_" -ForegroundColor Yellow
    }

  # Assign data plane role to managed identity (if identity exists)
  $identityId = az identity show --name $IdentityName --resource-group $ResourceGroup --query principalId -o tsv 2>$null
  if ($identityId) {
    Write-Host "🔑 Assigning role '$RoleName' to managed identity ($identityId)..."
    $max = 5; $i = 0
    while ($i -lt $max) {
      az role assignment create `
        --role $RoleName `
        --assignee-object-id $identityId `
        --assignee-principal-type ServicePrincipal `
        --scope $saId 1>$null 2>$null
      if ($LASTEXITCODE -eq 0) { Write-Host "   ✅ Role assignment succeeded"; break }
      Write-Host "   Retry role assignment (attempt $($i+1))..."; Start-Sleep -Seconds (3 * ($i+1)); $i++
    }
    if ($i -eq $max) { Write-Host "   ❌ Gave up assigning role after $max attempts" }
  } else {
    Write-Host "⚠️  Managed identity '$IdentityName' not found; skipping role assignment."
  }

    # If Keyless mode selected, explicitly disable shared key access post-creation (some API versions treat omit as true)
    # IMPORTANT: Always keep shared key access ENABLED for this staging account because the deployment script (newCert)
    # requires a key when an explicit scriptStorageAccountId is provided. Disabling it leads to KeyBasedAuthenticationNotPermitted.

        # NOTE: Do NOT set default-action Deny before deployment script runs; it needs public access when using account key.
        # Post-deployment hardening step could be added later.
  return $saId
}

# Create (if needed) a staging container and generate a user delegation SAS URL (read+list) without exposing account keys
function New-StagingContainerUserDelegationSas {
    param(
        [Parameter(Mandatory)][string]$StorageAccountName,
        [Parameter(Mandatory)][string]$ResourceGroup,
        [string]$ContainerName = 'scripts',
        [int]$HoursValid = 4,
        [int]$MaxRetries = 5
    )
    Write-Host "\n🗃️  Ensuring staging container '$ContainerName' (AAD auth, no account key)..."
    az storage container create --account-name $StorageAccountName --name $ContainerName --auth-mode login -o none 2>$null
    if ($LASTEXITCODE -ne 0) { Write-Host "⚠️  Could not create or confirm container '$ContainerName' (it may already exist)." }

    $expiry = (Get-Date).ToUniversalTime().AddHours($HoursValid).ToString('yyyy-MM-ddTHH:mmZ')
    $attempt = 0
    $sas = $null
    while ($attempt -lt $MaxRetries -and -not $sas) {
        $attempt++
        $out = az storage container generate-sas `
            --account-name $StorageAccountName `
            --name $ContainerName `
            --permissions rl `
            --expiry $expiry `
            --as-user `
            --auth-mode login -o tsv 2>&1
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($out)) {
            $sas = $out.Trim()
            break
        }
        if ($out -match 'There are no credentials provided' -or $out -match 'specify .*--auth-mode login') {
            Write-Host "⏳ RBAC propagation or role missing. Waiting before retry ($attempt/$MaxRetries)..."; Start-Sleep -Seconds (4 * $attempt)
        } elseif ($out -match 'AuthorizationPermissionMismatch' -or $out -match 'AuthorizationFailure') {
            Write-Host "❌ Authorization failure generating user delegation SAS. Ensure your signed-in principal (or managed identity) has 'Storage Blob Data Contributor' on the account. Raw: $out"
            break
        } else {
            Write-Host "⚠️  Attempt $attempt failed: $out"; Start-Sleep -Seconds (2 * $attempt)
        }
    }
    if (-not $sas) { Write-Host "❌ Failed to generate user delegation SAS after $MaxRetries attempts."; return $null }
    $url = "https://$StorageAccountName.blob.core.windows.net/$ContainerName`?$sas"
    Write-Host "🔑 Generated user delegation SAS URL (permissions=rl, expires=$expiry UTC)."
    Write-Host "   $url"
    return $url
}

# Ensure resource group
Invoke-EnsureResourceGroup -Name $resourceGroup -Location $location

# Ensure managed identity & optional custom role before staging storage creation
$managedIdentityId = Invoke-EnsureManagedIdentity -Name 'hpcpack-mi' -ResourceGroup $resourceGroup -Location $location
if ($managedIdentityId -and $EnableCustomRole) {
    Write-Host "\n🔧 -EnableCustomRole specified: attempting to create/ensure custom role from role.json"
    Invoke-EnsureCustomRoleFromFile -RoleName 'HPC-PACK Staging Storage Data Role' -SubscriptionId $subscriptionId
} elseif ($managedIdentityId) {
    Write-Host "\nℹ️  Skipping custom role creation (built-in 'Storage Blob Data Contributor' will be used). Use -EnableCustomRole to opt-in."
}

# NOTE: Preflight checks (module/file presence) were removed per user request.
# Ensure required 'bicep/shared' modules are present before running this script; the script will attempt to deploy directly.

# Defer creating staging storage account: the Bicep template creates the storage account and the
# user-assigned identity `userMiForNewCert`. We will only use an existing account if already present
# in the subscription/resource group. If not present, skip creation here and defer role assignment,
# SAS generation and account updates until after deployment when the template has provisioned it.
$SkippedStagingCreate = $false
$saId = $null
$existingSaJson = az storage account show --name $saName --resource-group $resourceGroup -o json 2>$null
if ($LASTEXITCODE -eq 0 -and $existingSaJson) {
    try { $existingSa = $existingSaJson | ConvertFrom-Json } catch { $existingSa = $null }
    if ($existingSa -and $existingSa.id) {
        Write-Host "ℹ️  Found existing staging storage account: $($existingSa.id)"
        $saId = $existingSa.id
    }
}
if (-not $saId) {
    Write-Host "ℹ️  Skipping local staging storage account creation; the Bicep template will provision the storage account and 'userMiForNewCert' identity. Role assignment, SAS generation, and account updates will be attempted after deployment when the storage account exists."
    $SkippedStagingCreate = $true
}

if ($SkippedStagingCreate) {
    Write-Host "🔑 Role assignment for staging storage account deferred until after deployment; storage account will be created by the Bicep template."
} else {
    # Deploy role assignment for storage account (assign Storage Blob Data Contributor to the managed identity)
    Write-Host "🔑 Assigning 'Storage Blob Data Contributor' role to managed identity for storage account..."

    # Resolve principalId for the managed identity (supports resource id or principalId)
    $principalId = $null
    if ($managedIdentityId -and ($managedIdentityId -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')) {
        # Looks like a GUID already (principalId)
        $principalId = $managedIdentityId
    } elseif ($managedIdentityId) {
        # Try to read principalId from the user-assigned identity resource id
        try {
            $principalId = az identity show --ids $managedIdentityId --query principalId -o tsv 2>$null
        } catch { $principalId = $null }
    }

    if (-not $principalId) {
        # As a final fallback, query by name in the resource group
        try {
            $principalId = az identity show --name 'hpcpack-mi' --resource-group $resourceGroup --query principalId -o tsv 2>$null
        } catch { $principalId = $null }
    }

    if (-not $principalId) {
        Write-Host "⚠️ Could not resolve managed identity principalId. Skipping explicit role assignment here (it may already have been attempted inside New-StagingStorageAccount)." -ForegroundColor Yellow
    } else {
        # Assign role at the storage account scope (resource id returned by New-StagingStorageAccount)
        $attempt = 0; $maxAttempts = 6; $assigned = $false
        while ($attempt -lt $maxAttempts -and -not $assigned) {
            $attempt++
            $out = az role assignment create --assignee-object-id $principalId --role "Storage Blob Data Contributor" --scope "$saId" 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Host "✅ Role assignment successful (attempt $attempt)."
                $assigned = $true
                break
            }
            # Retry on transient errors
            Write-Host "   Retry assigning role (attempt $attempt/$maxAttempts): $out" -ForegroundColor DarkYellow
            Start-Sleep -Seconds (3 * $attempt)
        }
        if (-not $assigned) {
            Write-Host "❌ Failed to assign role to managed identity after $maxAttempts attempts. Last output: $out" -ForegroundColor Red
        }
    }
}

if ($SkippedStagingCreate) {
    Write-Host "ℹ️  Skipping storage account update (min-tls and SAS expiration) because staging account creation was deferred to the Bicep template."
} else {
    az storage account update --resource-group $resourceGroup --name $saName --min-tls-version TLS1_2 --sas-expiration-period "7.00:00:00" -o none
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Failed to set SAS expiration period for the storage account." -ForegroundColor Red
    } else {
        Write-Host "✅ SAS expiration period set successfully."
    }
}

# If your environment requires a dedicated exempt staging account, create an exemption
# or re-run with an appropriate configuration. We will not set
# scriptStorageAccountId here to avoid failures when allowSharedKeyAccess is false.

# Option A: Generate a user delegation SAS URL only if explicitly requested AND in Keyless mode
$stagingScriptsSasUrl = $null
if ($GenerateStagingSas) {
    if ($SkippedStagingCreate) {
        Write-Host "ℹ️  SAS generation deferred until after deployment because staging storage account creation was skipped here. Once the template provisions the storage account, run the SAS generation step or rerun the script with -GenerateStagingSas post-deploy."
    } else {
        if ($StorageAuthMode -ne 'Keyless') {
            Write-Host "ℹ️  Skipping SAS generation (StorageAuthMode is '$StorageAuthMode'; requires 'Keyless')."
        } else {
            $stagingScriptsSasUrl = New-StagingContainerUserDelegationSas -StorageAccountName $saName -ResourceGroup $resourceGroup -ContainerName 'scripts' -HoursValid $StagingSasHours
            if ($stagingScriptsSasUrl) {
                Write-Host "ℹ️  Staging container SAS URL captured (not yet passed to template). Use this for read-only artifact distribution if needed." 
            }
        }
    }
}

# Attempt to grant Key Vault admin access before deployment (best-effort).
# This helps ensure the deployment scripts that need to access Key Vault can
# succeed when the signed-in user has the required RBAC. Failure to assign
# will not stop the deployment.
try {
    Write-Host "`n🔐 Attempting to configure Key Vault access permissions before deployment (best-effort)..."
    Grant-KeyVaultAdminAccess -ResourceGroupName $resourceGroup
} catch {
    Write-Host "⚠️ Could not assign Key Vault admin role pre-deployment: $_" -ForegroundColor Yellow
}

# Single validation + deployment via helper (includes validation inside)
$deploymentSuccess = Invoke-DeployHPCPackCluster -TemplateFile $TemplateFileAD -ResourceGroup $resourceGroup -Parameters $parameters

if (-not $deploymentSuccess) {
    Write-Host "`n⚠️  Deployment failed. Skipping post-deployment Key Vault configuration and repair steps." -ForegroundColor Yellow
}

# -------------------------------------------------------------------------------------------------
# Optional post-deployment repair path for failed newCert deployment script when policy blocks
# shared key access. This creates the certificate directly using Az.KeyVault cmdlets, leaving the
# failed deployment script resource as-is (no Bicep modifications required).
# -------------------------------------------------------------------------------------------------
if ($AutoRepairNewCert) {
    Write-Host "\n🛠️  AutoRepairNewCert enabled: Checking status of deployment script 'newCert'..."
    $ds = az resource show -g $resourceGroup -n newCert --resource-type Microsoft.Resources/deploymentScripts -o json 2>$null | ConvertFrom-Json
    if (-not $ds) {
        Write-Host "ℹ️  Deployment script resource 'newCert' not found (it may not have been deployed yet). Skipping repair."
    } else {
        $prov = $ds.properties.provisioningState
        if ($prov -eq 'Succeeded') {
            Write-Host "✅ newCert provisioningState is Succeeded. No repair needed."
        } elseif ($ds.properties.error -and ($ds.properties.error.message -match 'KeyBasedAuthenticationNotPermitted')) {
            Write-Host "❌ newCert failed with KeyBasedAuthenticationNotPermitted. Attempting direct Key Vault certificate creation..."
            # Locate Key Vault (assuming only one created by template in RG)
            $kvName = az resource list -g $resourceGroup --resource-type Microsoft.KeyVault/vaults --query "[0].name" -o tsv 2>$null
            if ([string]::IsNullOrWhiteSpace($kvName)) {
                Write-Host "❌ Unable to locate Key Vault in resource group '$resourceGroup'. Cannot perform repair."; return
            }
            Write-Host "🔍 Using Key Vault: $kvName"
            # Desired certificate name (from script content): HPCPackCommunication
            $certName = 'HPCPackCommunication'
            try {
                $existing = Get-AzKeyVaultCertificate -VaultName $kvName -Name $certName -ErrorAction SilentlyContinue
            } catch { $existing = $null }
            if ($existing) {
                Write-Host "ℹ️  Certificate '$certName' already exists in Key Vault '$kvName'. Repair not required.";
            } else {
                # Create self-signed cert replicating script logic
                $subject = 'CN=HPCPackCommunication'
                Write-Host "🏗️  Creating self-signed certificate '$certName' in Key Vault '$kvName' (subject $subject)..."
                try {
                    $policy = New-AzKeyVaultCertificatePolicy -SecretContentType 'application/x-pkcs12' -SubjectName $subject -IssuerName Self -ValidityInMonths 60 -ReuseKeyOnRenewal -KeyUsage DigitalSignature, KeyAgreement, KeyEncipherment, KeyCertSign -Ekus '1.3.6.1.5.5.7.3.1','1.3.6.1.5.5.7.3.2'
                    Add-AzKeyVaultCertificate -VaultName $kvName -Name $certName -CertificatePolicy $policy | Out-Null
                    Write-Host "⏳ Waiting for certificate materialization..."
                    Start-Sleep -Seconds 5
                    $tries = 0
                    do {
                        $created = Get-AzKeyVaultCertificate -VaultName $kvName -Name $certName -ErrorAction SilentlyContinue
                        if ($created -and $created.Thumbprint -and $created.SecretId) { break }
                        Start-Sleep -Seconds 2; $tries++
                    } while ($tries -lt 15)
                    if ($created -and $created.Thumbprint -and $created.SecretId) {
                        Write-Host "✅ Manual certificate creation succeeded. Thumbprint: $($created.Thumbprint)";
                        Write-Host "🔗 Secret URL: $($created.SecretId)";
                        Write-Host "⚠️  Note: The deployment script resource 'newCert' remains Failed in the portal. This is expected; you may ignore or delete it."
                    } else {
                        Write-Host "❌ Certificate creation did not complete in expected timeframe.";
                    }
                } catch {
                    Write-Host "❌ Exception during manual certificate creation: $_"
                }
            }
        } else {
            Write-Host "ℹ️  newCert provisioningState: $prov. Auto repair only handles KeyBasedAuthenticationNotPermitted failures."
        }
    }
}

# -----------------------------------------------------------------------------------------
# Post-deployment interactive decision helper
# Presents exactly the options previously surfaced in conversation for continuity:
#   1. Enable public network (and I'll update the vault + cert check).
#   2. Keep PNA disabled; guide me through private endpoint option.
#   3. Focus on policy exemption so deployment script (newCert) succeeds.
#   4. Something else (describe).
# Can also be driven non-interactively via -NextAction parameter with the exact strings.
# -----------------------------------------------------------------------------------------
function Invoke-PostDeploymentNextStep {
    param(
        [switch]$Menu,
        [switch]$DoCreatePrivateEndpoint,
        [int]$TempPublicSeconds,
        [string]$ResourceGroup,
        [string]$StagingAccountName,
        [string]$UserChoice,
        [string]$VnetName,
        [string]$SubnetName,
        [string]$PeName,
        [string]$DnsZoneRg,
        [string]$DnsZoneName
    )

    # Discover Key Vault (best-effort; may not exist if deployment failed earlier)
    $kvName = az resource list -g $ResourceGroup --resource-type Microsoft.KeyVault/vaults --query "[0].name" -o tsv 2>$null
    if (-not $kvName) {
        Write-Host "ℹ️  No Key Vault detected in resource group '$ResourceGroup'. Skipping next-step helper." -ForegroundColor Yellow
        return
    }

    function Enable-PublicNetworkOnKeyVault {
        param([string]$Name,[string]$Rg,[int]$TemporarySeconds = 0)
        Write-Host "🌐 Enabling public network access on Key Vault '$Name'..."
        $out = az keyvault update -n $Name -g $Rg --public-network-access Enabled 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "❌ Failed to enable public network access: $out" -ForegroundColor Red
            return
        }
        Write-Host "✅ Public network access enabled. Verifying certificate listing..."
        Start-Sleep -Seconds 3
        $certs = az keyvault certificate list --vault-name $Name -o json 2>$null | ConvertFrom-Json
        if ($certs) {
            $names = ($certs | Select-Object -ExpandProperty name)
            Write-Host "📜 Certificates now accessible: $($names -join ', ')"
        } else {
            Write-Host "⚠️  Still could not enumerate certificates (may be propagation delay). Try again shortly." -ForegroundColor Yellow
        }
        if ($TemporarySeconds -gt 0) {
            Write-Host "⏳ Waiting $TemporarySeconds seconds before re-disabling public network access..." -ForegroundColor DarkGray
            Start-Sleep -Seconds $TemporarySeconds
            Write-Host "🔐 Re-disabling public network access on Key Vault '$Name'..."
            $disable = az keyvault update -n $Name -g $Rg --public-network-access Disabled 2>&1
            if ($LASTEXITCODE -ne 0) { Write-Host "⚠️  Attempt to disable public access returned: $disable" -ForegroundColor Yellow } else { Write-Host "✅ Public network access disabled again." }
        }
    }

    function Show-PrivateEndpointGuidance {
        param([string]$Name,[string]$Rg)
        Write-Host "🔒 Private Endpoint Guidance for Key Vault '$Name'" -ForegroundColor Cyan
        Write-Host "Steps:" -ForegroundColor Cyan
        Write-Host "  1. Create (or choose) a VNet + subnet for private endpoint." -ForegroundColor Cyan
        Write-Host "  2. Run: az network private-endpoint create --name ${Name}-pe --resource-group $Rg --vnet-name <vnet> --subnet <subnet> --private-connection-resource-id $(az keyvault show -n $Name -g $Rg --query id -o tsv) --group-id vault --connection-name ${Name}-conn" -ForegroundColor DarkGray
        Write-Host "  3. Approve the connection if required (manual approval flow)." -ForegroundColor Cyan
        Write-Host "  4. Run from a VM/NIC inside that subnet (or with DNS resolving the private link FQDN)." -ForegroundColor Cyan
        Write-Host "  5. Keep public network access disabled for hardened posture." -ForegroundColor Cyan
    }

    function New-PrivateEndpointForKeyVault {
        param(
            [string]$Name,
            [string]$Rg,
            [string]$Vnet,
            [string]$Subnet,
            [string]$PeName,
            [string]$DnsZoneRg,
            [string]$DnsZoneName
        )
        if (-not $Vnet -or -not $Subnet) {
            Write-Host "❌ Missing -PrivateEndpointVnetName or -PrivateEndpointSubnetName. Cannot automate creation." -ForegroundColor Red; return
        }
        if (-not $PeName) { $PeName = "$Name-pe" }
        if (-not $DnsZoneRg) { $DnsZoneRg = $Rg }
        if (-not $DnsZoneName) { $DnsZoneName = 'privatelink.vaultcore.azure.net' }
        Write-Host "🔨 Creating private endpoint '$PeName' for Key Vault '$Name' in VNet '$Vnet'/'$Subnet'..."
        $kvId = az keyvault show -n $Name -g $Rg --query id -o tsv 2>$null
        if (-not $kvId) { Write-Host "❌ Could not resolve Key Vault resource ID." -ForegroundColor Red; return }
        az network private-endpoint show -g $Rg -n $PeName 1>$null 2>$null
        if ($LASTEXITCODE -ne 0) {
            $createPe = az network private-endpoint create --name $PeName --resource-group $Rg --vnet-name $Vnet --subnet $Subnet --private-connection-resource-id $kvId --group-id vault --connection-name ${PeName}-conn -o none 2>&1
            if ($LASTEXITCODE -ne 0) { Write-Host "❌ Failed creating private endpoint: $createPe" -ForegroundColor Red; return } else { Write-Host "✅ Private endpoint created." }
        } else { Write-Host "ℹ️  Private endpoint '$PeName' already exists." }

        # DNS zone
        az network private-dns zone show -g $DnsZoneRg -n $DnsZoneName 1>$null 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "🌐 Creating Private DNS zone '$DnsZoneName' in RG '$DnsZoneRg'..."
            $dnsCreate = az network private-dns zone create -g $DnsZoneRg -n $DnsZoneName -o none 2>&1
            if ($LASTEXITCODE -ne 0) { Write-Host "❌ Failed creating DNS zone: $dnsCreate" -ForegroundColor Red; return } else { Write-Host "✅ DNS zone created." }
        } else { Write-Host "ℹ️  DNS zone '$DnsZoneName' already exists." }

        $vnetId = az network vnet show -g $Rg -n $Vnet --query id -o tsv 2>$null
        if (-not $vnetId) { Write-Host "❌ Could not resolve VNet ID for link." -ForegroundColor Red; return }
        az network private-dns link vnet show -g $DnsZoneRg -z $DnsZoneName -n ${PeName}-link 1>$null 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "🔗 Creating VNet link to DNS zone..."
            $linkCreate = az network private-dns link vnet create -g $DnsZoneRg -n ${PeName}-link -z $DnsZoneName -v $vnetId --registration-enabled false -o none 2>&1
            if ($LASTEXITCODE -ne 0) { Write-Host "⚠️  VNet link create output: $linkCreate" -ForegroundColor Yellow } else { Write-Host "✅ VNet link created." }
        } else { Write-Host "ℹ️  VNet link already exists." }

        # DNS zone group association
        az network private-endpoint dns-zone-group show -g $Rg --private-endpoint-name $PeName -n ${PeName}-zonegroup 1>$null 2>$null
        $dnsZoneId = az network private-dns zone show -g $DnsZoneRg -n $DnsZoneName --query id -o tsv 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $dnsZoneId) { Write-Host "⚠️  Could not resolve DNS zone ID for zone group step." -ForegroundColor Yellow }
        if ($LASTEXITCODE -ne 0) {
            Write-Host "🧩 Creating DNS zone group association..."
            $zoneGroup = az network private-endpoint dns-zone-group create -g $Rg --private-endpoint-name $PeName -n ${PeName}-zonegroup --zone-name $DnsZoneName --private-dns-zone $dnsZoneId --record-set-name vault -o none 2>&1
            if ($LASTEXITCODE -ne 0) { Write-Host "⚠️  DNS zone group create output: $zoneGroup" -ForegroundColor Yellow } else { Write-Host "✅ DNS zone group created." }
        } else { Write-Host "ℹ️  DNS zone group already exists." }

        Write-Host "🎯 Private endpoint automation complete. Validate name resolution (nslookup $Name.vault.azure.net) from within the VNet." -ForegroundColor Green
    }

    function Show-PolicyExemptionGuidance {
        param([string]$StagingName,[string]$Rg)
        Write-Host "🛡️  Policy Exemption Guidance (allowSharedKeyAccess)" -ForegroundColor Cyan
        Write-Host "Your dedicated staging storage account: $StagingName" -ForegroundColor Cyan
        Write-Host "Recommended steps:" -ForegroundColor Cyan
        Write-Host "  1. Identify policy assignment denying allowSharedKeyAccess (likely at MG or tenant scope)." -ForegroundColor Cyan
        Write-Host "  2. Create an EXEMPTION scoped ONLY to: /subscriptions/$subscriptionId/resourceGroups/$Rg/providers/Microsoft.Storage/storageAccounts/$StagingName" -ForegroundColor Cyan
        Write-Host "  3. Justification: 'Temporary exemption for Key Vault deployment script staging (newCert)'." -ForegroundColor Cyan
        Write-Host "  4. Re-run this script WITHOUT -ForceProceedWithServiceManaged so newCert can succeed." -ForegroundColor Cyan
        Write-Host "  5. After successful certificate creation, optionally remove exemption or rotate to keyless pattern when platform supports it." -ForegroundColor Cyan
    }

    function Show-SomethingElsePlaceholder {
        Write-Host "🧭 You selected 'Something else'. Provide your custom requirement or rerun with -NextAction specifying one of the listed options." -ForegroundColor Yellow
    }

    $validSet = @(
        'Enable public network',
        'Keep PNA disabled; guide me through private endpoint option',
        'Focus on policy exemption so deployment script (newCert) succeeds',
        'Something else (describe)'
    )

    function Show-SelectionMenu {
        param([string[]]$Items)
        Write-Host "\n📋 What Do You Want Next?" -ForegroundColor Green
        for ($i=0; $i -lt $Items.Count; $i++) {
            $num = ($i+1).ToString().PadLeft(2,' ')
            Write-Host ("  [$num] {0}" -f $Items[$i])
        }
        Write-Host "  [ Q] Quit / cancel" -ForegroundColor DarkGray
        $attempt = 0
        while ($attempt -lt 5) {
            $ans = Read-Host "Enter a number (1-{0})" $Items.Count
            if ([string]::IsNullOrWhiteSpace($ans)) { $attempt++; continue }
            if ($ans -match '^[Qq]$') { return $null }
            if ($ans -match '^[0-9]+$') {
                $idx = [int]$ans - 1
                if ($idx -ge 0 -and $idx -lt $Items.Count) { return $Items[$idx] }
            }
            $attempt++
        }
        return $null
    }

    if (-not $UserChoice) {
        if ($Menu) {
            $selection = Show-SelectionMenu -Items $validSet
            if ($selection) {
                $UserChoice = $selection
            } else {
                Write-Host "❌ No valid selection made. Skipping post-deployment helper." -ForegroundColor Yellow
                return
            }
        } else {
            Write-Host "\nWhat Do You Want Next?" -ForegroundColor Green
            Write-Host "Reply with one of (or rerun with -UseMenu for numeric selection):" -ForegroundColor Green
            $validSet | ForEach-Object { Write-Host "  $_" }
            $UserChoice = Read-Host "Paste or type your choice"
        }
    }

    if (-not ($validSet -contains $UserChoice)) {
        Write-Host "❌ Unrecognized choice. Valid options are:" -ForegroundColor Red
        $validSet | ForEach-Object { Write-Host "  $_" }
        return
    }

    switch ($UserChoice) {
        'Enable public network' { Enable-PublicNetworkOnKeyVault -Name $kvName -Rg $ResourceGroup -TemporarySeconds $TempPublicSeconds }
        'Keep PNA disabled; guide me through private endpoint option' {
            if ($DoCreatePrivateEndpoint) {
                New-PrivateEndpointForKeyVault -Name $kvName -Rg $ResourceGroup -Vnet $VnetName -Subnet $SubnetName -PeName $PeName -DnsZoneRg $DnsZoneRg -DnsZoneName $DnsZoneName
            } else {
                Show-PrivateEndpointGuidance -Name $kvName -Rg $ResourceGroup
            }
        }
        'Focus on policy exemption so deployment script (newCert) succeeds' { Show-PolicyExemptionGuidance -StagingName $StagingAccountName -Rg $ResourceGroup }
        'Something else (describe)' { Show-SomethingElsePlaceholder }
    }
}

# Invoke next-step helper only after all other post-deployment steps so user context is clear
try {
    $resolvedNext = $NextAction
    if ($NextActionCode) {
        if ($NextAction) { Write-Host "⚠️ Both -NextAction and -NextActionCode supplied; -NextActionCode will override." -ForegroundColor Yellow }
        switch ($NextActionCode) {
            'EnablePna' { $resolvedNext = 'Enable public network' }
            'PrivateEndpoint' { $resolvedNext = 'Keep PNA disabled; guide me through private endpoint option' }
            'PolicyExemption' { $resolvedNext = 'Focus on policy exemption so deployment script (newCert) succeeds' }
            'Other' { $resolvedNext = 'Something else (describe)' }
        }
        Write-Host "🔁 Mapped -NextActionCode '$NextActionCode' to '$resolvedNext'" -ForegroundColor DarkCyan
    }
    $invokeParams = @{
        ResourceGroup = $resourceGroup
        StagingAccountName = $saName
        UserChoice = $resolvedNext
        TempPublicSeconds = $TemporaryPublicNetworkSeconds
        DoCreatePrivateEndpoint = $CreatePrivateEndpoint
        VnetName = $PrivateEndpointVnetName
        SubnetName = $PrivateEndpointSubnetName
        PeName = $PrivateEndpointName
        DnsZoneRg = $PrivateDnsZoneResourceGroup
        DnsZoneName = $PrivateDnsZoneName
        Menu = $UseMenu
    }
    Invoke-PostDeploymentNextStep @invokeParams
} catch {
    Write-Host "⚠️  Next-step helper encountered an error: $_" -ForegroundColor Yellow
}