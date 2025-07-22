#!/bin/bash
# AMLFS Network Troubleshooting and Mount Script

echo "🔧 AMLFS Network Troubleshooting and Mount Test"
echo "=============================================="

# Wait a moment for NSG rules to propagate
echo "⏳ Waiting for network security rules to propagate..."
sleep 10

echo "🔍 1. Testing network connectivity to AMLFS..."
echo "   Target: 10.242.1.5 (AMLFS MGS)"
echo "   Source: $(hostname -I | awk '{print $1}') (this VM)"

if ping -c 3 10.242.1.5; then
    echo "✅ Ping successful - Network connectivity OK"
    NETWORK_OK=true
else
    echo "❌ Ping still failing"
    NETWORK_OK=false
fi

echo ""
echo "🔍 2. Network diagnostics..."
echo "   Route table:"
ip route | grep 10.242.1
echo "   Network interfaces:"
ip a | grep -A 5 "inet 10.242.1"

if [ "$NETWORK_OK" = true ]; then
    echo ""
    echo "🔍 3. Testing Lustre-specific connectivity..."
    
    # Test TCP connectivity to common Lustre ports
    echo "   Testing TCP port 988 (Lustre)..."
    timeout 5 nc -z 10.242.1.5 988 && echo "   ✅ Port 988 accessible" || echo "   ❌ Port 988 not accessible"
    
    echo "   Testing TCP port 111 (portmapper)..."
    timeout 5 nc -z 10.242.1.5 111 && echo "   ✅ Port 111 accessible" || echo "   ❌ Port 111 not accessible"
    
    echo ""
    echo "🔍 4. Preparing for mount..."
    sudo mkdir -p /amlfs-prod-20250721-152206 
    echo "   ✅ Mount point /amlfs-prod-20250721-152206 created"
    
    echo ""
    echo "🔍 5. Checking Lustre client availability..."
    if which mount.lustre >/dev/null 2>&1; then
        echo "   ✅ Lustre client tools found"
        CLIENT_AVAILABLE=true
    else
        echo "   ❌ Lustre client tools not found"
        echo "   Checking for Lustre kernel modules..."
        if lsmod | grep -q lustre; then
            echo "   ✅ Lustre kernel modules loaded"
        else
            echo "   ❌ Lustre kernel modules not loaded"
        fi
        CLIENT_AVAILABLE=false
    fi
    
    echo ""
    echo "🔍 6. Attempting mount..."
    if [ "$CLIENT_AVAILABLE" = true ]; then
        echo "   Command: sudo mount -t lustre -o noatime,user_xattr 10.242.1.5@tcp0:/lustrefs /amlfs-prod-20250721-152206"
        
        if sudo mount -t lustre -o noatime,user_xattr 10.242.1.5@tcp0:/lustrefs /amlfs-prod-20250721-152206; then
            echo "   ✅ AMLFS mounted successfully!"
            echo ""
            echo "📊 Mount verification:"
            df -h /amlfs-prod-20250721-152206
            echo ""
            echo "📁 Directory listing:"
            ls -la /amlfs-prod-20250721-152206
            echo ""
            echo "🎉 AMLFS is ready for use at /amlfs-prod-20250721-152206"
        else
            echo "   ❌ Mount failed despite having Lustre client"
            echo "   Check dmesg for error messages:"
            echo "   sudo dmesg | tail -10"
        fi
    else
        echo "   ❌ Cannot attempt mount - Lustre client not available"
        echo ""
        echo "🛠️  Next steps to install Lustre client:"
        echo "   Option 1: Try Ubuntu packages (may not work on your kernel):"
        echo "   sudo apt-get update"
        echo "   sudo apt-get install lustre-client-modules-\$(uname -r)"
        echo ""
        echo "   Option 2: Use a CentOS/RHEL VM instead:"
        echo "   - CentOS has better Lustre package support"
        echo "   - Easier to install Lustre client"
        echo ""
        echo "   Option 3: Try alternative approach:"
        echo "   - Check if AMLFS supports NFS access"
        echo "   - Use containerized Lustre client"
    fi
else
    echo ""
    echo "❌ Network connectivity failed - cannot proceed with mount"
    echo ""
    echo "🛠️  Additional troubleshooting steps:"
    echo "1. Check VM network configuration:"
    echo "   sudo systemctl status systemd-networkd"
    echo ""
    echo "2. Check firewall on the VM:"
    echo "   sudo ufw status"
    echo ""
    echo "3. Verify NSG rules were applied:"
    echo "   az network nsg rule list --nsg-name amlfs-clientNSG --resource-group aml-rsj-managed-identity-20250721-1521 -o table"
fi

echo ""
echo "📋 System information:"
echo "   OS: $(lsb_release -d | cut -f2)"
echo "   Kernel: $(uname -r)"
echo "   VM IP: $(hostname -I | awk '{print $1}')"
echo "   Target: 10.242.1.5"
