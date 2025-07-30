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
- **Automated Virtual Network, subnet, and Network Security Group (NSG) creation for cluster nodes**  
- **InfiniBand (RDMA) support for HB120rs v3 nodes, including Mellanox WinOF2 driver installation and validation**  
---


## 🔑 Key Functions

### `Grant-KeyVaultAdminAccess`
Assigns the signed-in user the **Key Vault Administrator** role for the Key Vault in the specified resource group.

### `deploy_hpc_pack_cluster_ib.ps1`
Automates deployment of an HPC Pack cluster with InfiniBand (IB) support for HB120rs v3 nodes. This script:

- Creates a resource group, Virtual Network, subnet, and NSG with rules for RDP, SMB, and RDMA
- Deploys HB120rs v3 VMs into the subnet with accelerated networking
- Installs Mellanox WinOF2 drivers on each node and validates RDMA capability
- Outputs status for each step and ensures the cluster is RDMA/IB-ready

> **Note:** Update the script's network address ranges and admin credentials as needed for your environment.

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

### For Standard Cluster Deployment
1. Open PowerShell and run the script:
   ```powershell
   powershell -NoProfile -ExecutionPolicy Unrestricted -File .\deploy_hpc_pack_cluster.ps1
   ```
2. Select your Azure subscription from the GUI prompt.  
3. Enter the admin password when prompted.  
4. Optionally enter a custom authentication key.  
5. Monitor deployment progress in the Azure Portal.  


### For InfiniBand/RDMA Cluster Deployment (HB120rs v3)
1. Edit `deploy_hpc_pack_cluster_ib.ps1` to set your desired resource group, VNet, subnet, and admin credentials.
2. To perform a dry-run (no resources will be created, just validation):
   ```powershell
   powershell -NoProfile -ExecutionPolicy Unrestricted -File .\deploy_hpc_pack_cluster_ib.ps1 -DryRun
   ```
3. To run the actual deployment:
   ```powershell
   powershell -NoProfile -ExecutionPolicy Unrestricted -File .\deploy_hpc_pack_cluster_ib.ps1
   ```
4. The script will create the required network infrastructure, deploy HB120rs v3 VMs, and configure InfiniBand support automatically.  
5. Monitor deployment and driver installation status in the console and Azure Portal.  

---


## 📝 Notes

- The `deploy_hpc_pack_cluster_ib.ps1` script is designed for clusters requiring low-latency, high-throughput networking (RDMA/InfiniBand), such as MPI workloads.
- The script automates all network and firewall setup for the cluster nodes.
- Mellanox WinOF2 driver installation and RDMA validation are performed on each node.
- Monitor deployment status in the Azure Portal under **Resource Group > Deployments** and check VM console output for driver/IB status.

---

## 🔗 Resources

- **HPC Pack Templates Repository**  
  https://github.com/Azure/hpcpack-template/tree/master
