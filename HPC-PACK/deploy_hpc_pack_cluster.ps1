<#
.SYNOPSIS
    Deploys an HPC Pack Cluster in Azure with a single head node for Windows workloads,
    including the creation of a new Active Directory Domain.

.DESCRIPTION
    This PowerShell script automates the deployment of an HPC Pack cluster in Azure.
    It provisions a single-head-node cluster optimized for Windows workloads and sets up
    a new Active Directory domain as part of the deployment.

.AUTHOR
    Ricardo de Souza Jacomini

.DATE
    June 23, 2025

. Microsoft
    Azure HPC + AI

.NOTES
    ⚠️ Note on Validation Warnings:
    The warning "A nested deployment got short-circuited and all its resources got skipped from validation".
    It is a known behavior of Test-AzResourceGroupDeployment. It occurs when templates use runtime-dependent
    functions like reference() or resourceId()—especially when referencing outputs from nested deployments
    or resources not yet created. This is expected in complex templates and does not indicate a failure.
    You can safely proceed with New-AzResourceGroupDeployment for the actual deployment.

.LINK
    https://aka.ms/hpcgit
    https://github.com/Azure/hpcpack-template/tree/master
    https://github.com/Azure/hpcpack-template/blob/master/GeneratedTemplates/new-1hn-wincn-ad.json
#>

function Select-AzSubscriptionContext {
    $selectedSub = Get-AzSubscription | Out-GridView -Title "Select a subscription" -PassThru
    if (-not $selectedSub) {
        Write-Host "`n❌ No subscription selected. Exiting script."
        exit 1
    }
    Set-AzContext -SubscriptionId $selectedSub.Id -TenantId $selectedSub.TenantId
    return $selectedSub
}

function Ensure-ResourceGroup {
    param (
        [string]$Name,
        [string]$Location
    )
    if (Get-AzResourceGroup -Name $Name -ErrorAction SilentlyContinue) {
        Write-Host "Resource group '$Name' exists."
        $confirmation = Read-Host "Do you want to remove the existing resource group '$Name'? (Y/N)"
        if ($confirmation -eq "Y") {
            Remove-AzResourceGroup -Name $Name -Force
            Write-Host "Resource group '$Name' has been removed."
            New-AzResourceGroup -Name $Name -Location $Location
        } else {
            Write-Host "Keeping the existing resource group."
        }
    } else {
        Write-Host "Creating resource group '$Name'..."
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
        New-AzResourceGroupDeployment -ResourceGroupName $ResourceGroup -TemplateFile $TemplateFile @Parameters -Verbose -Debug
        Write-Host "✅ Deployment initiated. Monitor in Azure Portal."
    } catch {
        Write-Host "❌ Deployment failed: $_"
    }
}

# Main Execution
$TemplateFileAD = "new-1hn-wincn-ad.json"
$resourceGroup = "tes-hpc-pack"
$location = "East US"
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
    computeNodeNumber = 2
    computeNodeImage = "WindowsServer2022_Gen2"
    computeNodeVMSize = "Standard_E2s_v3"
    computeNodeOsDiskType = "Standard_HDD"
    computeNodeDataDiskCount = 1
    computeNodeDataDiskSize = 32
    computeNodeDataDiskType = "Standard_HDD"
    availabilitySetOption = "Auto"
    enableManagedIdentityOnHeadNode = "No"
    createPublicIPAddressForHeadNode = "No"
    enableAcceleratedNetworking = "No"
    enableAzureMonitor = "No"
    useVmssForComputeNodes = "No"
    useSpotInstanceForComputeNodes = "No"
    autoInstallInfiniBandDriver = "No"
}

Ensure-ResourceGroup -Name $resourceGroup -Location $location
Deploy-HPCPackCluster -TemplateFile $TemplateFileAD -ResourceGroup $resourceGroup -Parameters $parameters

# function that encapsulates the logic for retrieving the Key Vault resource and assigning the Key Vault Administrator role to the signed-in user
# Grant-KeyVaultAdminAccess -ResourceGroupName $resourceGroup
