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

.NOTES
    - Validation warnings such as "A nested deployment got short-circuited and all its resources got skipped from validation" are expected when using Test-AzResourceGroupDeployment with complex ARM templates. These do not indicate deployment failure.
    - For production use, review and update parameters such as VM sizes, admin credentials, and domain names as appropriate for your environment.
    - Monitor deployment progress and status in the Azure Portal under Resource Group > Deployments.

.LINK
    https://aka.ms/hpcgit
    https://github.com/Azure/hpcpack-template/tree/master
    https://github.com/Azure/hpcpack-template/blob/master/GeneratedTemplates/new-1hn-wincn-ad.json
#>

function Select-AzSubscriptionContext {
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
        Write-Host "❌ Error accessing subscriptions: $($_.Exception.Message)"
        Write-Host "Try running: Connect-AzAccount"
        Write-Host "Or: Update-Module Az -Force"
        exit 1
    }
}

function Ensure-ResourceGroup {
    param (
        [string]$Name,
        [string]$Location
    )
    if (Get-AzResourceGroup -Name $Name -ErrorAction SilentlyContinue) {
        Write-Host "Resource group '$Name' exists."
        Write-Host "⚠️  Previous deployments may have left the resource group in an inconsistent state."
        $confirmation = Read-Host "Do you want to remove the existing resource group '$Name' and start fresh? (Y/N)"
        if ($confirmation -eq "Y") {
            Write-Host "🗑️  Removing existing resource group and all resources..."
            Remove-AzResourceGroup -Name $Name -Force
            Write-Host "✅ Resource group '$Name' has been removed."
            Write-Host "📦 Creating new resource group..."
            New-AzResourceGroup -Name $Name -Location $Location
        } else {
            Write-Host "⚠️  Keeping existing resource group. This may cause deployment dependency issues."
            Write-Host "💡 Consider using a different resource group name if deployment fails."
        }
    } else {
        Write-Host "📦 Creating resource group '$Name'..."
        New-AzResourceGroup -Name $Name -Location $Location
    }
}

function Get-AuthenticationKey {
    param ([string]$SubscriptionId)
    $authInput = Read-Host -Prompt "Enter authentication key (press Enter to use 'subscriptionId: $SubscriptionId')"
    if ([string]::IsNullOrWhiteSpace($authInput)) {
        Write-Host "Using default authentication key: subscriptionId: $SubscriptionId"
        return ConvertTo-SecureString "subscriptionId: $SubscriptionId" -AsPlainText -Force
    } else {
        return ConvertTo-SecureString $authInput -AsPlainText -Force
    }
}

function Grant-KeyVaultAdminAccess {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName
    )

    try {
        $keyVault = Get-AzKeyVault -ResourceGroupName $ResourceGroupName -ErrorAction Stop
        $scope = $keyVault.ResourceId
        $objectId = (Get-AzADUser -SignedIn).Id

        Write-Host "🔐 Assigning 'Key Vault Administrator' role to the signed-in user..."
        New-AzRoleAssignment -ObjectId $objectId -RoleDefinitionName "Key Vault Administrator" -Scope $scope -ErrorAction Stop
        Write-Host "✅ Role assignment successful for Key Vault: $($keyVault.VaultName)"
    }
    catch {
        Write-Host "❌ Failed to assign Key Vault role: $_"
    }
}

function Deploy-HPCPackCluster {
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
        $validation = Test-AzResourceGroupDeployment -ResourceGroupName $ResourceGroup -TemplateFile $TemplateFile @Parameters -ErrorAction SilentlyContinue
        
        if ($validation) {
            Write-Host "⚠️  Template validation found potential issues:"
            $validation | ForEach-Object { Write-Host "   • $($_.Message)" }
            Write-Host "ℹ️  Note: Some warnings about nested deployments are expected and don't indicate failure."
        } else {
            Write-Host "✅ Template validation passed."
        }
        
        Write-Host "`n📊 Starting deployment..."
        
        $deployment = New-AzResourceGroupDeployment -ResourceGroupName $ResourceGroup -TemplateFile $TemplateFile @Parameters -Verbose
        
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

# Main Execution
$TemplateFileAD = "new-1hn-wincn-ad.json"
$timestamp = Get-Date -Format "MMddHHmm"
$resourceGroup = "hpcpack-wn-jacomini-$timestamp"
$location = "East US 2"  # Updated to use working region based on deployment analysis
$clusterName = "headnode"
$domainName = "hpc.cluster"
$adminUsername = "hpcadmin"
$adminPassword = Read-Host -Prompt "Enter admin password" -AsSecureString

$selectedSub = Select-AzSubscriptionContext
$subscriptionId = $selectedSub.Id
$authenticationKey = Get-AuthenticationKey -SubscriptionId $subscriptionId

# Configuration
$parameters = @{
    adminUsername = $adminUsername
    adminPassword = $adminPassword
    authenticationKey = $authenticationKey
    clusterName = $clusterName
    domainName = $domainName
    domainControllerVMSize = "Standard_E2s_v3"
    headNodeOS = "WindowsServer2022"
    headNodeVMSize = "Standard_D4s_v3"
    headNodeOsDiskType = "Standard_HDD"
    headNodeDataDiskCount = 1
    headNodeDataDiskSize = 128
    headNodeDataDiskType = "Standard_HDD"
    computeNodeNamePrefix = "IaaSCN"
    computeNodeNumber = 1
    computeNodeImage = "WindowsServer2022_Gen2"
    computeNodeVMSize = "Standard_E2s_v3"
    computeNodeOsDiskType = "Standard_HDD"
    computeNodeDataDiskCount = 1
    computeNodeDataDiskSize = 32
    computeNodeDataDiskType = "Standard_HDD"
    availabilitySetOption = "Auto"
    enableManagedIdentityOnHeadNode = "Yes"
    createPublicIPAddressForHeadNode = "Yes"
    enableAcceleratedNetworking = "No"
    enableAzureMonitor = "No"
    useVmssForComputeNodes = "No"
    useSpotInstanceForComputeNodes = "No"
    autoInstallInfiniBandDriver = "No"
}

Ensure-ResourceGroup -Name $resourceGroup -Location $location
$deploymentSuccess = Deploy-HPCPackCluster -TemplateFile $TemplateFileAD -ResourceGroup $resourceGroup -Parameters $parameters

# Only try to grant Key Vault access if deployment was successful
if ($deploymentSuccess) {
    Write-Host "`n🔐 Configuring Key Vault access permissions post-deployment..."
    Grant-KeyVaultAdminAccess -ResourceGroupName $resourceGroup
} else {
    Write-Host "`n⚠️  Skipping Key Vault access configuration due to deployment failure."
    Write-Host "💡 To resolve permission issues, contact your Azure administrator for:"
    Write-Host "   • User Access Administrator role on subscription: $subscriptionId"
    Write-Host "   • Or Owner permissions on resource group: $resourceGroup"
}
