#!/bin/bash
# Quick AMLFS Mount Test Script

echo "🔍 Testing AMLFS connectivity and mount..."
echo "==========================================="

# Check network connectivity to AMLFS MGS
echo "1. Testing connectivity to AMLFS MGS (10.242.1.5)..."
if ping -c 3 10.242.1.5 > /dev/null 2>&1; then
    echo "✅ Ping to 10.242.1.5 successful"
else
    echo "❌ Ping to 10.242.1.5 failed"
    echo "   Check network configuration and security groups"
    exit 1
fi

# Check if mount point exists
echo "2. Preparing mount point..."
sudo mkdir -p /mnt/amlfs
echo "✅ Mount point /mnt/amlfs ready"

# Try to mount
echo "3. Attempting to mount AMLFS..."
echo "   Command: sudo mount -t lustre -o noatime,user_xattr 10.242.1.5@tcp0:/lustrefs /mnt/amlfs"

if sudo mount -t lustre -o noatime,user_xattr 10.242.1.5@tcp0:/lustrefs /mnt/amlfs; then
    echo "✅ AMLFS mounted successfully!"
    echo ""
    echo "📊 Mount verification:"
    df -h /mnt/amlfs
    echo ""
    echo "📁 Directory listing:"
    ls -la /mnt/amlfs
    echo ""
    echo "🎉 AMLFS is ready for use at /mnt/amlfs"
else
    echo "❌ Mount failed. Checking possible causes..."
    
    # Check if lustre modules are loaded
    echo "   Checking Lustre kernel modules..."
    if lsmod | grep -q lustre; then
        echo "   ✅ Lustre modules are loaded"
    else
        echo "   ❌ Lustre modules not found"
        echo "   This is likely the issue. Lustre client needs to be installed."
        
        echo ""
        echo "🔧 Troubleshooting steps:"
        echo "1. Check kernel version: uname -r"
        echo "2. Try installing: sudo apt-get install lustre-client-modules-\$(uname -r)"
        echo "3. If not available, consider:"
        echo "   - Using CentOS/RHEL VM instead"
        echo "   - Building Lustre from source"
        echo "   - Using NFS access (if supported)"
        
        echo ""
        echo "📋 Your system info:"
        echo "   Kernel: $(uname -r)"
        echo "   OS: $(lsb_release -d | cut -f2)"
        echo "   IP: $(hostname -I | awk '{print $1}')"
    fi
fi
