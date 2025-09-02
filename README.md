# Microsoft HPC and AI - Deployment Solutions and Technical Documentation
Comprehensive deployment guides and automation scripts for Microsoft Azure High Performance Computing (HPC) and Artificial Intelligence (AI) solutions

> **📝 Personal Notes Disclaimer**  
> This document contains personal notes created by **Ricardo S Jacomini - Azure HPC & AI SEE**.  
> **This is NOT an official Microsoft document** and represents personal insights and experiences.

# HPC-PACK Deployment

This folder contains resources to deploy an HPC Pack Cluster in Microsoft Azure.

## Overview

The deployment sets up:
- An HPC Pack Cluster tailored for Windows workloads.
- A single head node configuration.
- A new Active Directory Domain as part of the deployment process.

This setup is ideal for high-performance computing scenarios that require Windows-based infrastructure and centralized domain management.

## Prerequisites

- Azure subscription
- Appropriate permissions to deploy resources and create Active Directory domains

## Deployment

Follow the instructions in the deployment scripts or templates provided in this folder to initiate the setup.

### Quick Start

📁 **[HPC-PACK](./HPC-PACK/)** - Main deployment folder containing all necessary scripts and templates

# Azure Managed Lustre File System (AMLFS) Deployment

This repository provides comprehensive Bicep templates and automation scripts for deploying Azure Managed Lustre File Systems (AMLFS) with different security and feature configurations.

## 🚀 Choose Your Deployment Version

### **📋 Quick Comparison**

| Feature | Basic Version | Managed Identity Version |
|---------|---------------|--------------------------|
| **🎯 Use Case** | Testing & Development | Production Workloads |
| **🔐 Authentication** | User credentials | Managed Identity |
| **🛡️ RBAC Setup** | Manual | Automatic |
| **📦 HSM Support** | ❌ | ✅ Blob storage integration |
| **🗄️ Storage Container** | ❌ | ✅ Private container |
| **🔒 Security Level** | Basic NSG rules | Enhanced + Lustre ports |
| **🔄 Credential Management** | Manual rotation | Automatic |
| **📊 Audit Trail** | Limited | Full via managed identity |
| **⚙️ Complexity** | Simple | Advanced |
| **⏱️ Setup Time** | ~5 minutes | ~10 minutes |

---

## 📁 Available Solutions

### 🟦 **Option 1: Basic Version** 
**📖 [Complete Documentation: README-basic.md](AMLFS/README-basic.md)**

**Perfect for: Development, Testing, Quick Prototyping**

```powershell
# Quick start - Basic version
.\AMLFS\scripts\Test-AMLFSZones.ps1 -ResourceGroup "aml-rsj" -Location "eastus"
```

**📋 What you get:**
- ✅ Clean, minimal Bicep template
- ✅ Automated zone testing
- ✅ Basic network security
- ✅ 8TiB AMLFS Premium-250
- ✅ Simple deployment process

**📁 Files:**
- `AMLFS/templates/infra-basic.bicep` - Minimal template
- `AMLFS/scripts/Test-AMLFSZones.ps1` - Zone testing script
- `AMLFS/README-basic.md` - Complete documentation

---

### 🟩 **Option 2: Managed Identity Version**
**📖 [Complete Documentation: README-managed-identity.md](AMLFS/README-managed-identity.md)**

**Perfect for: Production, Enterprise, Security-First Deployments**

```powershell
# Quick start - Managed identity version
.\AMLFS\scripts\Test-AMLFSZones-ManagedIdentity.ps1 -ResourceGroup "aml-rsj-managed-identity" -Location "eastus"
```

**🏆 What you get:**
- ✅ User-Assigned Managed Identity
- ✅ Automatic RBAC role assignments
- ✅ HSM (Hierarchical Storage Management)
- ✅ Private blob container
- ✅ Enhanced security rules
- ✅ Production-ready configuration

**📁 Files:**
- `AMLFS/templates/infra-managed-identity.bicep` - Full-featured template
- `AMLFS/scripts/Test-AMLFSZones-ManagedIdentity.ps1` - Advanced testing script
- `AMLFS/README-managed-identity.md` - Complete documentation

---

## 🎯 Decision Guide

### **Choose Basic Version if:**
- 🧪 You're **testing or developing** AMLFS solutions
- ⚡ You need **quick deployment** with minimal configuration
- 🎓 You're **learning** AMLFS concepts
- 💰 You want **minimal resource overhead**
- 🔧 You prefer **manual control** over security settings

**👉 [Go to Basic Documentation](AMLFS/README-basic.md)**

### **Choose Managed Identity Version if:**
- 🏢 You're deploying for **production workloads**
- 🔐 You need **enterprise-grade security**
- 📊 You require **audit trails** and compliance
- 🗂️ You want **HSM data tiering** capabilities
- 🤖 You prefer **automated credential management**
- 👥 You're working in **multi-tenant environments**

**👉 [Go to Managed Identity Documentation](AMLFS/README-managed-identity.md)**

---

## 📚 Common Prerequisites

Both versions require:

1. **Azure CLI** installed and configured
2. **PowerShell 5.1+** (for Windows automation scripts)
3. **Azure Login**: `az login`
4. **Proper permissions**: Contributor role (Basic) or User Access Administrator (Managed Identity)

## 🔍 Pre-Deployment Checks

Before using either version, run these commands to verify readiness:

```powershell
# Check AMLFS quota and availability
az rest --method GET --url "https://management.azure.com/subscriptions/$(az account show --query id -o tsv)/providers/Microsoft.StorageCache/locations/eastus/usages?api-version=2023-05-01"

# Verify StorageCache provider is registered
az provider list --query "[?namespace=='Microsoft.StorageCache'].{Namespace:namespace, State:registrationState}" -o table
```

## 🚀 Quick Start Commands

### Basic Version:
```powershell
# Test and deploy basic version
.\AMLFS\scripts\Test-AMLFSZones.ps1 -ResourceGroup "aml-rsj" -Location "eastus"
```
**📖 [Full Basic Guide →](AMLFS/README-basic.md)**

### Managed Identity Version:
```powershell
# Test and deploy managed identity version
$resourceGroup = "amlfs-managed-identity-$(Get-Date -Format 'yyyyMMdd-HHmm')"
.\AMLFS\scripts\Test-AMLFSZones-ManagedIdentity.ps1 -ResourceGroup $resourceGroup -Location "eastus"
```
**📖 [Full Managed Identity Guide →](AMLFS/README-managed-identity.md)**

## 🛠️ Repository Structure

```
📂 AMLFS Deployment Repository
├── 📄 README.md                           # This overview file
├── 📄 AMLFS/README-basic.md               # Basic version documentation
├── 📄 AMLFS/README-managed-identity.md    # Managed identity version documentation
├── 📁 AMLFS/templates/                    # Infrastructure templates
│   ├── 🧩 infra-basic.bicep                   # Basic Bicep template
│   ├── 🧩 infra-managed-identity.bicep        # Managed identity Bicep template
│   ├── 🧩 infra.bicep                         # Legacy template
│   └── � infra-managed-identity.json         # Parameters file
├── �📁 AMLFS/scripts/                      # Automation scripts
│   ├── 🤖 Test-AMLFSZones.ps1                # Basic version zone testing
│   ├── 🤖 Test-AMLFSZones-ManagedIdentity.ps1 # Managed identity zone testing
│   ├── 🤖 next-steps.ps1                     # Post-deployment automation
│   ├── 🤖 create-vm.ps1                      # VM creation with fallbacks
│   ├── 🤖 Check-ManagedIdentityPermissions.ps1 # Permission validation
│   ├── 🧩 kernel-downgrade.sh                # Lustre client installation
│   └── 📋 Various utility scripts
└── 📁 AMLFS/pictures/                     # Documentation images
    └── 🖼️ diagram.png                        # Architecture diagram
```

## 📖 Documentation Links

- **🟦 [README-basic.md](AMLFS/README-basic.md)** - Complete guide for basic AMLFS deployment
- **🟩 [README-managed-identity.md](AMLFS/README-managed-identity.md)** - Complete guide for managed identity deployment

## ✅ Verified Status

Both solutions have been **tested and validated**:

- ✅ **Zone Testing**: All zones (1, 2, 3) verified available in East US
- ✅ **Deployment Automation**: Scripts working correctly  
- ✅ **Template Validation**: Bicep templates compile successfully
- ✅ **Documentation**: Complete setup and troubleshooting guides
- ✅ **Managed Identity Deployment**: Successfully deployed with fresh resource group pattern
- ✅ **HSM Post-Deployment**: Process documented for production workloads

## 🆘 Getting Help

- **Basic Version Issues**: See [README-basic.md](AMLFS/README-basic.md) → Troubleshooting section
- **Managed Identity Issues**: See [README-managed-identity.md](AMLFS/README-managed-identity.md) → Troubleshooting section
- **Common Problems**: BCP081 warnings are expected and safe to ignore
- **Capacity Issues**: Use the automated zone testing to find available zones

## 🎉 Success Stories

Both templates provide:
- **Automated zone availability testing** - No more guesswork on capacity
- **Flexible deployment options** - Choose your zone (1, 2, or 3)
- **Complete documentation** - Step-by-step guides with examples
- **Production-ready code** - Tested and validated templates

---

## 🎯 When to Choose Lustre for Your Workloads

You'll want to use Lustre when your workloads demand extreme I/O performance, massive parallelism, and low-latency access to large datasets — especially in high-performance computing (HPC) and AI scenarios.

### 🚀 Ideal Use Cases for Lustre

| Scenario | Why Lustre Excels |
|----------|-------------------|
| **MPI-based HPC workloads** | Parallel file access with RDMA support |
| **AI/ML training** | Fast access to large datasets, especially with GPUs |
| **Genomics & Bioinformatics** | Handles millions of small files with high throughput |
| **Seismic & CFD simulations** | Sustains multi-GB/s reads/writes across compute nodes |
| **Financial modeling** | Low-latency access for time-sensitive calculations |
| **Video rendering & processing** | High bandwidth for large media files |

**💡 Key Insight:** Lustre is designed to keep up with your compute, not slow it down. It's used in supercomputers like Frontier and Fugaku, and powers many of the world's top 100 HPC clusters.

### 🧠 Lustre's Decision Matrix

Since you're already working with MPI, RDMA, and AMLFS:
- ✅ **Use Lustre (via AMLFS)** when you need parallel I/O across many nodes
- 📂 **Stick with Managed Disks or NFS** for simpler, single-node workloads  
- 💰 **Consider Blob integration with AMLFS** to tier cold data cost-effectively

---

## 📚 References

### Official Microsoft Documentation
- **[Azure Managed Lustre File System Documentation](https://docs.microsoft.com/en-us/azure/azure-managed-lustre/)** - Official Azure AMLFS documentation
- **[HPC Pack Documentation](https://docs.microsoft.com/en-us/powershell/high-performance-computing/overview)** - Microsoft HPC Pack official guide
- **[Azure Bicep Documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)** - Infrastructure as Code with Bicep
- **[Azure RBAC Documentation](https://docs.microsoft.com/en-us/azure/role-based-access-control/)** - Role-Based Access Control guide

### Lustre File System Resources
- **[Lustre.org](https://www.lustre.org/)** - Official Lustre project website
- **[Lustre Operations Manual](https://doc.lustre.org/lustre_manual.xhtml)** - Comprehensive Lustre administration guide
- **[OpenSFS Foundation](https://www.opensfs.org/)** - Open Scalable File Systems community

### High-Performance Computing References
- **[Top500 Supercomputers](https://www.top500.org/)** - List of world's fastest supercomputers
- **[Exascale Computing Project](https://www.exascaleproject.org/)** - US Department of Energy HPC initiative
- **[OpenMPI Documentation](https://www.open-mpi.org/)** - Message Passing Interface implementation

### Azure Architecture & Best Practices
- **[Azure Well-Architected Framework](https://docs.microsoft.com/en-us/azure/architecture/framework/)** - Design principles for Azure solutions
- **[Azure HPC Architecture](https://docs.microsoft.com/en-us/azure/architecture/topics/high-performance-computing)** - HPC patterns and practices
- **[Azure Storage Performance Guide](https://docs.microsoft.com/en-us/azure/storage/common/storage-performance-checklist)** - Storage optimization strategies

### Community & Support
- **[Azure HPC Tech Community](https://techcommunity.microsoft.com/t5/azure-high-performance-computing/ct-p/AzureHighPerformanceComputing)** - Microsoft Tech Community for HPC
- **[Stack Overflow - Azure HPC](https://stackoverflow.com/questions/tagged/azure+hpc)** - Community Q&A for Azure HPC
- **[GitHub - Azure HPC Examples](https://github.com/Azure/azurehpc)** - Official Azure HPC samples and templates

---

**🌟 Start with the version that matches your needs, and you'll have AMLFS running in minutes!**

**Quick Navigation:**
- **🟦 [Basic Version Documentation →](AMLFS/README.md)**
- **🟩 [Managed Identity Version Documentation →](AMLFS/README-managed-identity.md)**
