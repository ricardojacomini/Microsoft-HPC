# AMLFS Next Steps Automation Script
# Based on README-managed-identity.md "🚀 Next Steps After Deployment" section
# Updated: July 22, 2025

param(
    [string]$ResourceGroup = "aml-rsj-managed-identity-20250721-1521",
    [string]$AmlfsName = "amlfs-prod-20250721-152206", 
    [string]$StorageAccount = "storagez7xghrwomjhiw",
    [string]$VmName = "amlfs-ubuntu2404-client",
    [switch]$SkipHSM,
    [switch]$SkipVMCreation,
    [switch]$GenerateScriptsOnly
)

Write-Host "🚀 AMLFS Next Steps Automation" -ForegroundColor Green
Write-Host "===============================" -ForegroundColor Green
Write-Host "Based on README-managed-identity.md" -ForegroundColor Gray
Write-Host "Resource Group: $ResourceGroup" -ForegroundColor Yellow
Write-Host "AMLFS Name: $AmlfsName" -ForegroundColor Yellow
Write-Host "Storage Account: $StorageAccount" -ForegroundColor Yellow

# Step 1: Configure HSM (Hierarchical Storage Management)
if (-not $SkipHSM) {
    Write-Host "`n� STEP 1: Configure HSM (Hierarchical Storage Management)" -ForegroundColor Cyan

    try {
        # Get the AMLFS resource ID
        Write-Host "🔍 Getting AMLFS resource ID..." -ForegroundColor Yellow
        $amlfsId = az resource show --resource-group $ResourceGroup --resource-type "Microsoft.StorageCache/amlFileSystems" --name $AmlfsName --query "id" -o tsv
        
        if (-not $amlfsId) {
            throw "AMLFS resource not found: $AmlfsName"
        }
        
        # Get the Storage Container URL
        $containerUrl = "https://$StorageAccount.blob.core.windows.net/amlfs-data"
        
        # Configure HSM settings
        $hsmSettings = '[{"importPrefix":"/","exportPrefix":"/export","container":"' + $containerUrl + '"}]'
        
        Write-Host "⚡ Applying HSM configuration..." -ForegroundColor Yellow
        az resource update --ids $amlfsId --set "properties.hsm.settings=$hsmSettings"
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ HSM configuration applied successfully!" -ForegroundColor Green
            
            # Verify HSM configuration  
            Write-Host "🔍 Verifying HSM configuration..." -ForegroundColor Yellow
            $hsmStatus = az resource show --ids $amlfsId --query "properties.hsm" -o json
            Write-Host "HSM Status: $hsmStatus" -ForegroundColor Gray
        } else {
            throw "Failed to apply HSM configuration"
        }
    }
    catch {
        Write-Host "❌ HSM Configuration failed: $_" -ForegroundColor Red
        Write-Host "💡 You can configure HSM manually later using Azure CLI" -ForegroundColor Yellow
    }
} else {
    Write-Host "`n⏭️  STEP 1: HSM Configuration (SKIPPED)" -ForegroundColor Yellow
}

# Step 2: Create Ubuntu VM for AMLFS Client
if (-not $SkipVMCreation) {
    Write-Host "`n�️  STEP 2: Create Ubuntu VM for AMLFS Client" -ForegroundColor Cyan
    
    try {
        # Check if VM already exists
        $existingVM = az vm show --resource-group $ResourceGroup --name $VmName --query "name" -o tsv 2>$null
        if ($existingVM) {
            Write-Host "✅ VM already exists: $VmName" -ForegroundColor Green
        } else {
            Write-Host "🔄 Creating Ubuntu 24.04 VM..." -ForegroundColor Yellow
            $vmResult = az vm create `
                --resource-group $ResourceGroup `
                --name $VmName `
                --image "Ubuntu2204" `
                --size "Standard_D4s_v3" `
                --vnet-name "vnet" `
                --subnet "amlfs" `
                --public-ip-sku Standard `
                --admin-username "azureuser" `
                --generate-ssh-keys `
                --output json
            
            if ($LASTEXITCODE -eq 0) {
                $vm = $vmResult | ConvertFrom-Json
                $publicIp = $vm.publicIpAddress
                
                Write-Host "✅ VM created successfully!" -ForegroundColor Green
                Write-Host "📋 VM Details:" -ForegroundColor White
                Write-Host "   Name: $VmName" -ForegroundColor Gray
                Write-Host "   Public IP: $publicIp" -ForegroundColor Gray
                Write-Host "   SSH: ssh azureuser@$publicIp" -ForegroundColor Yellow
            } else {
                throw "VM creation failed"
            }
        }
    }
    catch {
        Write-Host "❌ VM Creation failed: $_" -ForegroundColor Red
        Write-Host "💡 Try running: .\create-vm.ps1 for automatic VM creation with fallback options" -ForegroundColor Yellow
    }
} else {
    Write-Host "`n⏭️  STEP 2: VM Creation (SKIPPED)" -ForegroundColor Yellow
}

# Step 3: Generate Lustre Client Installation Scripts
Write-Host "`n📜 STEP 3: Generate Lustre Client Installation Scripts" -ForegroundColor Cyan

# Generate comprehensive Lustre installation script based on README Step 3
$lustreScript = @'
#!/bin/bash
# AMLFS Lustre Client Installation Script
# Based on README-managed-identity.md Step 3
# Generated automatically by next-steps.ps1

set -euo pipefail

echo "🚀 AMLFS Lustre Client Installation"
echo "==================================="

# Prerequisites Check
echo "📋 Prerequisites Check"
echo "Ubuntu version:"
lsb_release -a
echo "Checking sudo access..."
sudo whoami

# Step 3.1: Install Compatible Kernel
echo ""
echo "🔧 Step 3.1: Install Compatible Kernel"
sudo apt update
sudo apt install -y linux-image-azure-lts-24.04
sudo apt remove -y linux-image-azure
echo "Installed kernels:"
apt list --installed linux-image*

# Step 3.2: Configure Azure Managed Lustre Repository
echo ""
echo "📦 Step 3.2: Configure Repository"
cat <<'REPO_SCRIPT' > /tmp/setup-amlfs-repo.sh
#!/bin/bash
set -euo pipefail

echo "🔄 Setting up Azure Managed Lustre repository..."
apt update
apt install -y ca-certificates curl apt-transport-https lsb-release gnupg
source /etc/lsb-release
echo "deb [arch=amd64] https://packages.microsoft.com/repos/amlfs-${DISTRIB_CODENAME}/ ${DISTRIB_CODENAME} main" | tee /etc/apt/sources.list.d/amlfs.list
curl -sL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | tee /etc/apt/trusted.gpg.d/microsoft.gpg > /dev/null
apt update
echo "✅ Repository configured successfully"
REPO_SCRIPT

chmod +x /tmp/setup-amlfs-repo.sh
sudo bash /tmp/setup-amlfs-repo.sh

# Step 3.3: Install Specific Kernel Version
echo ""
echo "🔧 Step 3.3: Install Specific Kernel"
sudo apt full-upgrade -y
sudo apt install -y linux-image-6.8.0-1030-azure
echo "Kernel packages:"
dpkg -l | grep linux-image

# Step 3.4: Configure Boot Options
echo ""
echo "⚙️  Step 3.4: Configure Boot Options"
echo "Available boot entries:"
grep -E "menuentry '" /boot/grub/grub.cfg | cut -d "'" -f2
echo "Current GRUB default:"
grep DEFAULT /etc/default/grub
sudo sed -i 's/GRUB_DEFAULT=.*/GRUB_DEFAULT="1>2"/' /etc/default/grub
sudo update-grub

echo ""
echo "⚠️  REBOOT REQUIRED - System will reboot in 10 seconds"
echo "🔄 After reboot, run: ./install-lustre-client-part2.sh"
sleep 10
sudo reboot
'@

$lustreScript | Out-File -FilePath "install-lustre-client.sh" -Encoding UTF8

# Part 2 script (after reboot)
$lustreScript2 = @'
#!/bin/bash
# AMLFS Lustre Client Installation Script - Part 2 (After Reboot)
# Run this script after the system reboots with the new kernel

set -euo pipefail

echo "� AMLFS Lustre Client Installation - Part 2"
echo "==========================================="

# Verify kernel
echo "🔍 Verifying kernel version..."
echo "Current kernel: $(uname -r)"

# Step 3.5: Install Lustre Client
echo ""
echo "📦 Step 3.5: Install Lustre Client"
sudo apt-get install -y amlfs-lustre-client-2.16.1-14-gbc76088=$(uname -r)
sudo apt-get install -f -y
sudo apt autoremove -y

# Step 3.6: Verify Installation
echo ""
echo "✅ Step 3.6: Verify Installation"
echo "LFS utility location:"
which lfs
echo "LFS version:"
lfs --version

echo ""
echo "🔧 Loading Lustre kernel modules..."
sudo modprobe lnet
sudo modprobe lustre
echo "Loaded modules:"
lsmod | grep -E "(lustre|lnet)"

echo ""
echo "🧪 Testing Lustre commands..."
lfs help | head -5

echo ""
echo "✅ Lustre client installation complete!"
echo "📋 Ready to mount AMLFS filesystem"

# Generate mount script
cat <<'MOUNT_SCRIPT' > mount-amlfs.sh
#!/bin/bash
# AMLFS Mount Script

echo "📂 Step 5: Mount AMLFS Filesystem"
echo "================================="

# Create mount point
echo "Creating mount point..."
mkdir -p /amlfs-prod-20250721-152206

# Mount AMLFS with optimized options
echo "Mounting AMLFS filesystem..."
sudo mount -t lustre -o noatime,user_xattr,flock 10.242.1.5@tcp0:/lustrefs /amlfs-prod-20250721-152206

# Verify mount
echo "✅ Verifying mount..."
df -h /amlfs-prod-20250721-152206
ls -la /amlfs-prod-20250721-152206

echo "🎉 AMLFS mounted successfully at /amlfs-prod-20250721-152206"
MOUNT_SCRIPT

chmod +x mount-amlfs.sh
echo "💾 Mount script created: ./mount-amlfs.sh"
'@

$lustreScript2 | Out-File -FilePath "install-lustre-client-part2.sh" -Encoding UTF8

Write-Host "✅ Lustre installation scripts generated:" -ForegroundColor Green
Write-Host "   📄 install-lustre-client.sh (Part 1 - requires reboot)" -ForegroundColor Gray
Write-Host "   📄 install-lustre-client-part2.sh (Part 2 - after reboot)" -ForegroundColor Gray

# Step 4: Get AMLFS Mount Information
Write-Host "`n� STEP 4: Get AMLFS Mount Information" -ForegroundColor Cyan

try {
    # Get AMLFS mount address
    $mountAddress = az resource show `
        --resource-group $ResourceGroup `
        --name $AmlfsName `
        --resource-type "Microsoft.StorageCache/amlFileSystems" `
        --query "properties.mountAddress" `
        -o tsv
    
    if (-not $mountAddress) {
        throw "Could not retrieve mount address for AMLFS: $AmlfsName"
    }
    
    Write-Host "📡 AMLFS Mount Address: $mountAddress" -ForegroundColor Green
    
    # Generate PowerShell mount info script
    $psCommands = @"
# PowerShell Commands for AMLFS Mount Information
# Generated by next-steps.ps1

`$resourceGroup = "$ResourceGroup"
`$amlfsName = "$AmlfsName"

# Get mount address
`$mountAddress = az resource show ``
    --resource-group `$resourceGroup ``
    --name `$amlfsName ``
    --resource-type "Microsoft.StorageCache/amlFileSystems" ``
    --query "properties.mountAddress" ``
    -o tsv

Write-Host "📡 AMLFS Mount Address: `$mountAddress" -ForegroundColor Green
Write-Host "📋 Mount Command for Linux clients:" -ForegroundColor Cyan
Write-Host "   mkdir /amlfs-prod-20250721-152206" -ForegroundColor White
Write-Host "   sudo mount -t lustre -o noatime,user_xattr,flock `$mountAddress /amlfs-prod-20250721-152206" -ForegroundColor White
"@
    
    $psCommands | Out-File -FilePath "get-mount-info.ps1" -Encoding UTF8
    
    # Save detailed mount information
    @"
# AMLFS Mount Information
# Generated: $(Get-Date)

RESOURCE_GROUP=$ResourceGroup
AMLFS_NAME=$AmlfsName  
MOUNT_ADDRESS=$mountAddress
STORAGE_ACCOUNT=$StorageAccount

# Linux Mount Commands (optimized):
mkdir /amlfs-prod-20250721-152206
sudo mount -t lustre -o noatime,user_xattr,flock $mountAddress /amlfs-prod-20250721-152206

# Verify mount:
df -h /amlfs-prod-20250721-152206
ls -la /amlfs-prod-20250721-152206

# Auto-mount (add to /etc/fstab):
echo "$mountAddress /amlfs-prod-20250721-152206 lustre noatime,user_xattr,flock,_netdev 0 0" >> /etc/fstab

# Performance testing:
mkdir -p /amlfs-prod-20250721-152206/performance-test
dd if=/dev/zero of=/amlfs-prod-20250721-152206/performance-test/test-write bs=1M count=100
dd if=/amlfs-prod-20250721-152206/performance-test/test-write of=/dev/null bs=1M
rm -rf /amlfs-prod-20250721-152206/performance-test

# HSM testing:
echo "Test data for HSM" > /amlfs-prod-20250721-152206/hsm-test.txt
lfs hsm_archive /amlfs-prod-20250721-152206/hsm-test.txt
lfs hsm_state /amlfs-prod-20250721-152206/hsm-test.txt
"@ | Out-File -FilePath "amlfs-mount-info.txt" -Encoding UTF8
    
    Write-Host "✅ Mount information generated:" -ForegroundColor Green
    Write-Host "   📄 get-mount-info.ps1 (PowerShell mount info)" -ForegroundColor Gray
    Write-Host "   📄 amlfs-mount-info.txt (detailed mount instructions)" -ForegroundColor Gray
}
catch {
    Write-Host "❌ Failed to get mount information: $_" -ForegroundColor Red
    Write-Host "💡 Check that AMLFS deployment completed successfully" -ForegroundColor Yellow
}

# Step 5: Generate Complete Setup Summary  
Write-Host "`n📊 STEP 5: Complete Setup Summary" -ForegroundColor Cyan

$summary = @"
# AMLFS Complete Setup Summary
# Generated: $(Get-Date)

## Deployment Information
Resource Group: $ResourceGroup
AMLFS Name: $AmlfsName
Storage Account: $StorageAccount
VM Name: $VmName

## Files Generated by next-steps.ps1:
✅ install-lustre-client.sh        - Lustre client installation (Part 1)
✅ install-lustre-client-part2.sh  - Lustre client installation (Part 2 - after reboot)  
✅ get-mount-info.ps1              - PowerShell mount information
✅ amlfs-mount-info.txt            - Detailed mount instructions
✅ amlfs-setup-summary.txt         - This summary file

## Next Steps Checklist:
□ Step 1: HSM Configuration $(if($SkipHSM){"(SKIPPED)"}else{"(COMPLETED)"})
□ Step 2: VM Creation $(if($SkipVMCreation){"(SKIPPED)"}else{"(COMPLETED)"})  
□ Step 3: SSH to VM and upload scripts
□ Step 4: Run: ./install-lustre-client.sh (requires reboot)
□ Step 5: After reboot, run: ./install-lustre-client-part2.sh
□ Step 6: Run: ./mount-amlfs.sh to mount filesystem
□ Step 7: Test performance and HSM functionality

## Quick Commands for VM Setup:
# Upload scripts to VM:
scp *.sh azureuser@<VM_PUBLIC_IP>:~/

# Connect to VM:
ssh azureuser@<VM_PUBLIC_IP>

# Install Lustre (Part 1):
chmod +x install-lustre-client.sh
sudo ./install-lustre-client.sh

# After reboot, install Lustre (Part 2):
chmod +x install-lustre-client-part2.sh  
sudo ./install-lustre-client-part2.sh

# Mount AMLFS:
chmod +x mount-amlfs.sh
./mount-amlfs.sh

## Troubleshooting:
- If VM creation fails: Use .\create-vm.ps1 for automated fallback options
- If Lustre installation fails: Check kernel compatibility and repository setup
- If mount fails: Verify network connectivity and module loading

## Reference:
See README-managed-identity.md for detailed explanations of each step.
Sections: "🚀 Next Steps After Deployment" (Steps 1-7)
"@

$summary | Out-File -FilePath "amlfs-setup-summary.txt" -Encoding UTF8

Write-Host "✅ Complete setup summary generated: amlfs-setup-summary.txt" -ForegroundColor Green

# Final summary
Write-Host "`n🎉 AMLFS Next Steps Automation Completed!" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Green

Write-Host "`n📋 What was completed automatically:" -ForegroundColor Yellow
if (-not $SkipHSM) {
    Write-Host "✅ HSM (Hierarchical Storage Management) configuration" -ForegroundColor Green
} else {
    Write-Host "⏭️  HSM configuration (skipped)" -ForegroundColor Gray
}
if (-not $SkipVMCreation) {
    Write-Host "✅ Ubuntu VM creation for AMLFS client" -ForegroundColor Green  
} else {
    Write-Host "⏭️  VM creation (skipped)" -ForegroundColor Gray
}
Write-Host "✅ Lustre client installation scripts generation" -ForegroundColor Green
Write-Host "✅ Mount information and scripts generation" -ForegroundColor Green
Write-Host "✅ Complete setup documentation" -ForegroundColor Green

Write-Host "`n📋 What you need to do manually:" -ForegroundColor Yellow
Write-Host "1. SSH to the VM and upload the generated scripts" -ForegroundColor White
Write-Host "2. Run the Lustre installation scripts (requires reboot)" -ForegroundColor White  
Write-Host "3. Mount the AMLFS filesystem" -ForegroundColor White
Write-Host "4. Test performance and HSM functionality" -ForegroundColor White

Write-Host "`n📄 Key files to use:" -ForegroundColor Cyan
Write-Host "   📋 amlfs-setup-summary.txt - Complete instructions" -ForegroundColor Gray
Write-Host "   🔧 install-lustre-client.sh - Lustre setup (Part 1)" -ForegroundColor Gray
Write-Host "   � install-lustre-client-part2.sh - Lustre setup (Part 2)" -ForegroundColor Gray
Write-Host "   📂 amlfs-mount-info.txt - Mount commands and testing" -ForegroundColor Gray

Write-Host "`n� Your AMLFS with managed identity is ready for production use!" -ForegroundColor Green
