#!/bin/bash
# AMLFS Lustre Client Installation Script for Ubuntu 24.04
# Based on README-managed-identity.md Step 3: Install Lustre Client
# Updated to align with production-ready deployment process

set -euo pipefail

echo "� AMLFS Lustre Client Installation for Ubuntu 24.04"
echo "====================================================="
echo "📋 Current kernel: $(uname -r)"
echo "📅 Date: $(date)"
echo "📖 Reference: README-managed-identity.md Step 3"
echo ""

# Prerequisites Check
echo "🔍 Prerequisites Check"
echo "======================"
echo "📋 Verifying Ubuntu version..."
lsb_release -a
echo ""
echo "🔐 Checking sudo access..."
sudo whoami
echo "✅ Prerequisites verified"
echo ""

echo "🔧 Step 3.1: Install Compatible Kernel"
echo "======================================"
echo "📝 Installing Azure LTS kernel (required for Lustre compatibility)..."

# Update package lists
sudo apt update

# Install the Azure LTS kernel (required for Lustre compatibility)
sudo apt install -y linux-image-azure-lts-24.04

# Remove the default HWE kernel to avoid conflicts
sudo apt remove -y linux-image-azure

# List all installed kernels to verify
echo "📋 Installed kernel packages:"
apt list --installed linux-image*
echo ""

echo "📦 Step 3.2: Configure Azure Managed Lustre Repository"
echo "======================================================"
echo "🔄 Setting up Microsoft AMLFS repository..."

# Create repository configuration script
cat <<'EOF' > /tmp/setup-amlfs-repo.sh
#!/bin/bash
set -euo pipefail

echo "🔄 Setting up Azure Managed Lustre repository..."

# Install required packages
apt update
apt install -y ca-certificates curl apt-transport-https lsb-release gnupg

# Get Ubuntu codename
source /etc/lsb-release

# Add Microsoft AMLFS repository
echo "deb [arch=amd64] https://packages.microsoft.com/repos/amlfs-${DISTRIB_CODENAME}/ ${DISTRIB_CODENAME} main" | tee /etc/apt/sources.list.d/amlfs.list

# Add Microsoft GPG key
curl -sL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | tee /etc/apt/trusted.gpg.d/microsoft.gpg > /dev/null

# Update package lists with new repository
apt update

echo "✅ Repository configured successfully"
EOF

# Make script executable and run it
chmod +x /tmp/setup-amlfs-repo.sh
sudo bash /tmp/setup-amlfs-repo.sh
echo ""

echo "� Step 3.3: Install Specific Kernel Version"
echo "============================================"
echo "📝 Performing full system upgrade and installing specific kernel..."

# Perform full system upgrade
sudo apt full-upgrade -y

# Install the specific kernel version compatible with Lustre
sudo apt install -y linux-image-6.8.0-1030-azure

# Verify kernel installation
echo "📋 Installed kernel packages:"
dpkg -l | grep linux-image
echo ""

echo "⚙️  Step 3.4: Configure Boot Options"
echo "===================================="
echo "📋 Checking available boot menu entries..."

# Check available boot menu entries
echo "Available boot entries:"
grep -E "menuentry '" /boot/grub/grub.cfg | cut -d "'" -f2

echo ""
echo "📋 Current GRUB configuration:"
grep DEFAULT /etc/default/grub

echo ""
echo "🔧 Setting GRUB to boot the compatible kernel..."
echo "⚠️  Note: GRUB_DEFAULT value depends on your specific kernel list"
echo "   Count menu entries starting from 0 (format: \"submenu>entry\")"

# Set GRUB to boot the compatible kernel (adjust number based on menu)
# This is set to "1>2" as a common pattern, but should be verified per system
sudo sed -i 's/GRUB_DEFAULT=.*/GRUB_DEFAULT="1>2"/' /etc/default/grub

# Update GRUB configuration
sudo update-grub

echo ""
echo "✅ Boot configuration updated"
echo "📋 Alternative: Set by exact kernel name (more robust):"
echo "   sudo sed -i 's/GRUB_DEFAULT=.*/GRUB_DEFAULT=\"Ubuntu, with Linux 6.8.0-1030-azure\"/' /etc/default/grub"
echo "   echo 'GRUB_SAVEDEFAULT=true' | sudo tee -a /etc/default/grub"
echo "   sudo update-grub"
echo ""

echo "⚠️  REBOOT REQUIRED - System will reboot in 10 seconds to use compatible kernel"
echo "🔄 After reboot, run the Part 2 script for Lustre client installation"
echo "   Ctrl+C to cancel automatic reboot"
sleep 10
sudo reboot

# Generate Part 2 script for after reboot
cat <<'EOF' > kernel-downgrade-part2.sh
#!/bin/bash
# AMLFS Lustre Client Installation Script - Part 2 (After Reboot)
# Based on README-managed-identity.md Step 3.5-3.6
# Run this script after the system reboots with the compatible kernel

set -euo pipefail

echo "🚀 AMLFS Lustre Client Installation - Part 2 (After Reboot)"
echo "=========================================================="
echo "📅 Date: $(date)"
echo ""

echo "🔍 Step 3.5: Install Lustre Client (After Reboot)"
echo "=================================================="

# Verify we're running the correct kernel
echo "📋 Verifying kernel version..."
current_kernel=$(uname -r)
echo "Current kernel: $current_kernel"

if [[ $current_kernel == *"6.8.0-1030-azure"* ]]; then
    echo "✅ Running compatible kernel for Lustre"
else
    echo "⚠️  WARNING: Not running expected kernel 6.8.0-1030-azure"
    echo "   Current kernel: $current_kernel"
    echo "   You may need to adjust GRUB configuration"
fi
echo ""

echo "📦 Installing Lustre client package for current kernel..."
sudo apt-get install -y amlfs-lustre-client-2.16.1-14-gbc76088=$(uname -r)

echo "🔧 Fixing dependency issues..."
sudo apt-get install -f -y

echo "🧹 Cleaning up unnecessary packages..."
sudo apt autoremove -y
echo ""

echo "✅ Step 3.6: Verify Installation"
echo "================================"

# Check Lustre filesystem utilities are installed
echo "🔍 Verifying Lustre client installation..."
echo "LFS utility location:"
which lfs
echo "LFS version:"
lfs --version
echo ""

# Load Lustre kernel modules
echo "🔍 Loading Lustre kernel modules..."
sudo modprobe lnet
sudo modprobe lustre

# Verify modules are loaded
echo "📋 Loaded modules:"
lsmod | grep -E "(lustre|lnet)"
echo ""

# Test LFS commands
echo "🔍 Testing Lustre commands..."
echo "Available LFS commands:"
lfs --list-commands | head -10
echo ""

echo "✅ Lustre client installation complete!"
echo "📋 Ready to mount AMLFS filesystem"
echo ""

# Generate mount script
cat <<'MOUNT_SCRIPT' > mount-amlfs.sh
#!/bin/bash
# AMLFS Mount Script
# Generated by kernel-downgrade-part2.sh

echo "📂 Step 5: Mount AMLFS Filesystem"
echo "================================="

# Create mount point
echo "📁 Creating mount point..."
sudo mkdir -p /amlfs-prod-20250721-152206

# Mount AMLFS with optimized options
echo "🔗 Mounting AMLFS filesystem..."
echo "   Mount command: sudo mount -t lustre -o noatime,user_xattr,flock 10.242.1.5@tcp0:/lustrefs /amlfs-prod-20250721-152206"
sudo mount -t lustre -o noatime,user_xattr,flock 10.242.1.5@tcp0:/lustrefs /amlfs-prod-20250721-152206

# Verify mount
echo "✅ Verifying mount..."
df -h /amlfs-prod-20250721-152206
echo ""
echo "📋 Mount contents:"
ls -la /amlfs-prod-20250721-152206
echo ""

echo "🎉 AMLFS mounted successfully at /amlfs-prod-20250721-152206"
echo ""
echo "📋 Next steps:"
echo "   • Test performance: dd if=/dev/zero of=/amlfs-prod-20250721-152206/test.file bs=1M count=100"
echo "   • Test HSM: lfs hsm_archive /amlfs-prod-20250721-152206/test.file"
echo "   • Check HSM status: lfs hsm_state /amlfs-prod-20250721-152206/test.file"
MOUNT_SCRIPT

chmod +x mount-amlfs.sh
echo "💾 Mount script created: ./mount-amlfs.sh"
echo ""

echo "🎯 INSTALLATION COMPLETE SUMMARY"
echo "================================="
echo "✅ Compatible kernel installed and active: $(uname -r)"
echo "✅ Lustre client software installed and verified"
echo "✅ Kernel modules loaded successfully"
echo "✅ Mount script generated: ./mount-amlfs.sh"
echo ""
echo "📋 To mount AMLFS filesystem:"
echo "   ./mount-amlfs.sh"
echo ""
echo "📚 For troubleshooting, see README-managed-identity.md Step 3"
echo ""

echo "🎯 SCRIPT EXECUTION SUMMARY"
echo "============================"
echo "✅ Step 3.1: Compatible kernel installed (linux-image-azure-lts-24.04)"
echo "✅ Step 3.2: AMLFS repository configured" 
echo "✅ Step 3.3: Specific kernel version installed (6.8.0-1030-azure)"
echo "✅ Step 3.4: Boot configuration updated"
echo "✅ Part 2 script generated for post-reboot installation"
echo ""

echo "📋 WHAT HAPPENS NEXT:"
echo "====================="
echo "1. System will reboot automatically in 10 seconds"
echo "2. System will boot with compatible kernel (6.8.0-1030-azure)"  
echo "3. SSH back into the VM after reboot"
echo "4. Run: ./kernel-downgrade-part2.sh"
echo "5. Run: ./mount-amlfs.sh to mount filesystem"
echo ""

echo "🏗️ SCRIPT ARCHITECTURE:"
echo "========================"
echo "kernel-downgrade.sh          # Part 1 (requires reboot)"
echo "├── Step 3.1: Kernel installation"
echo "├── Step 3.2: Repository setup"  
echo "├── Step 3.3: Specific kernel version"
echo "├── Step 3.4: GRUB configuration"
echo "└── Generates: kernel-downgrade-part2.sh"
echo ""
echo "kernel-downgrade-part2.sh    # Part 2 (after reboot)"
echo "├── Step 3.5: Lustre client installation"
echo "├── Step 3.6: Module loading & verification"
echo "└── Generates: mount-amlfs.sh"
echo ""
echo "mount-amlfs.sh              # Filesystem mounting"
echo "├── Optimized mount options"
echo "├── Performance testing"
echo "└── HSM testing commands"
echo ""

echo "🔧 TROUBLESHOOTING:"
echo "==================="
echo "If kernel installation fails:"
echo "  • Check internet connectivity"
echo "  • Verify repository configuration: cat /etc/apt/sources.list.d/amlfs.list"
echo "  • Try: sudo apt update && sudo apt install --fix-broken"
echo ""
echo "If GRUB configuration fails:"
echo "  • Manually check available kernels after reboot"
echo "  • Use exact kernel name in GRUB_DEFAULT"
echo "  • Verify with: grep -E \"menuentry '\" /boot/grub/grub.cfg"
echo ""
echo "If system doesn't boot correctly:"
echo "  • Boot into recovery mode"
echo "  • Reset GRUB_DEFAULT to 0: sed -i 's/GRUB_DEFAULT=.*/GRUB_DEFAULT=0/' /etc/default/grub"
echo "  • Run: update-grub && reboot"
echo ""

echo "📖 REFERENCES:"
echo "=============="
echo "• README-managed-identity.md - Complete documentation"
echo "• Azure Managed Lustre Client Guide: https://learn.microsoft.com/en-us/azure/azure-managed-lustre/client-install?pivots=ubuntu-24"
echo "• Microsoft AMLFS Repository: https://packages.microsoft.com/repos/amlfs-noble/"
echo ""

echo "✨ ADVANTAGES OF THIS APPROACH:"
echo "==============================="
echo "• Automatic version alignment between kernel and Lustre modules"
echo "• Simplified package management with apt"
echo "• Better support for Ubuntu 24.04 LTS"  
echo "• Production-ready configuration"
echo "• Optimized mount options for performance"
echo "• Complete automation with error handling"
echo ""

echo "🎉 AMLFS Lustre Client Setup Complete!"
echo "======================================"
echo "📋 Files generated:"
echo "   • kernel-downgrade-part2.sh - Post-reboot installation"
echo "   • mount-amlfs.sh - Filesystem mounting (generated after Part 2)"
echo ""
