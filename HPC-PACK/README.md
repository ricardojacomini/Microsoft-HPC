# HPC Pack Cluster Deployment Script

## 📌 Overview

This PowerShell script automates the deployment of an HPC Pack cluster in Azure. It provisions a single-head-node cluster optimized for Windows workloads and sets up a new Active Directory domain.

### The deployment includes:

- Azure Resource Group creation  
- Head node and compute node provisioning  
- Active Directory domain setup  
- Optional Key Vault access configuration  

---

## 👤 Author

**Ricardo de Souza Jacomini**  
Microsoft Azure HPC + AI  
📅 Date: June 23, 2025

---

## ✅ Prerequisites

Before running this script, ensure the following:

- Azure PowerShell module (`Az`) is installed  
- Contributor access to the target Azure subscription  
- Access to a custom image (if using `headNodeImageResourceId` or `computeNodeImageResourceId`)  
- Permissions to assign roles in Azure Key Vault (if using Key Vault integration)  

---

## ⚙️ Script Features

- Interactive Azure subscription selection  
- Secure admin password prompt  
- Optional authentication key override  
- Resource group validation and recreation  
- Parameterized deployment using ARM templates  
- Role assignment for Key Vault access  

---

## 🔑 Key Functions

### `Grant-KeyVaultAdminAccess`

Assigns the signed-in user the **Key Vault Administrator** role for the Key Vault in the specified resource group.

```powershell
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
```

---

## 🧩 Deployment Parameters

The script supports the following parameters (defined in the ARM template):

| Parameter                    | Description                                | Example                    |
|-----------------------------|--------------------------------------------|----------------------------|
| `hpcPackRelease`            | HPC Pack version                           | `"2019 Update 3"`          |
| `clusterName`               | Name of the HPC cluster                    | `"my-hpc-cluster"`         |
| `domainName`                | AD domain name                             | `"hpc.cluster"`            |
| `headNodeOS`, `computeNodeImage` | OS versions                             | `"WindowsServer2019"`      |
| `headNodeVMSize`, `computeNodeVMSize` | VM sizes                         | `"Standard_D4s_v3"`         |
| `headNodeDataDiskSize`, `computeNodeDataDiskSize` | Disk sizes         | `128`                      |
| `enableAzureMonitor`        | Enable Azure Monitor                       | `true`                     |
| `enableAcceleratedNetworking` | Enable accelerated networking            | `true`                     |

---

## 🚀 Usage

1. Open PowerShell and run the script.  
2. Select your Azure subscription from the GUI prompt.  
3. Enter the admin password when prompted.  
4. Optionally enter a custom authentication key.  
5. Monitor deployment progress in the Azure Portal.  

---

## 📝 Notes

- The script uses `New-AzResourceGroupDeployment` for ARM-based provisioning.  
- Validation warnings related to nested deployments are expected and safe to ignore.  
- Monitor deployment status in the Azure Portal under **Resource Group > Deployments**.  

---

## 🔗 Resources

- **HPC Pack Templates Repository**  
  https://github.com/Azure/hpcpack-template/tree/master
