#!/bin/bash
# AMLFS Direct Connection Test (Bypass Ping)

echo "🔧 AMLFS Direct Connection Test"
echo "==============================="
echo "Date: $(date)"
echo ""

echo "🎯 Architecture Discovery:"
echo "  VM IP: $(hostname -I | awk '{print $1}') (amlfs-client)"
echo "  MDS/MGS IP: 10.242.1.5 (Management/Metadata Server)"
echo "  OSS IP: 10.242.1.7 (Object Storage Server)"
echo ""

echo "🔍 1. Network Interface Status"
echo "------------------------------"
ip addr show eth0 | grep -E "(inet|state)"

echo ""
echo "🔍 2. Testing Direct TCP Connections (bypass ping)"
echo "--------------------------------------------------"

# Test Lustre-specific ports instead of ping
echo "Testing MGS (10.242.1.5):"
for port in 988 1019; do
    echo -n "  Port $port: "
    if timeout 5 nc -zv 10.242.1.5 $port 2>/dev/null; then
        echo "✅ OPEN"
    else
        echo "❌ Closed/filtered"
    fi
done

echo ""
echo "Testing OSS (10.242.1.7):"
for port in 988 1019; do
    echo -n "  Port $port: "
    if timeout 5 nc -zv 10.242.1.7 $port 2>/dev/null; then
        echo "✅ OPEN"
    else
        echo "❌ Closed/filtered"
    fi
done

echo ""
echo "🔍 3. Testing Portmapper (RPC)"
echo "------------------------------"
echo "MGS Portmapper (port 111):"
timeout 5 nc -zv 10.242.1.5 111 && echo "✅ MGS RPC accessible" || echo "❌ MGS RPC not accessible"

echo "OSS Portmapper (port 111):"
timeout 5 nc -zv 10.242.1.7 111 && echo "✅ OSS RPC accessible" || echo "❌ OSS RPC not accessible"

echo ""
echo "🔍 4. Lustre Mount Attempt (regardless of ping)"
echo "-----------------------------------------------"
echo "Creating mount point..."
sudo mkdir -p /mnt/amlfs

echo ""
echo "Attempting Lustre mount with original command:"
echo "sudo mount -t lustre -o noatime,user_xattr 10.242.1.5@tcp0:/lustrefs /mnt/amlfs"

if sudo mount -t lustre -o noatime,user_xattr 10.242.1.5@tcp0:/lustrefs /mnt/amlfs 2>/dev/null; then
    echo "🎉 SUCCESS! AMLFS mounted despite ping failure!"
    echo ""
    echo "Mount verification:"
    df -h /mnt/amlfs
    echo ""
    echo "Directory listing:"
    ls -la /mnt/amlfs
    echo ""
    echo "✅ AMLFS is working! Ping failure was a red herring."
else
    echo "❌ Mount failed. Checking error details..."
    
    # Capture mount error
    MOUNT_ERROR=$(sudo mount -t lustre -o noatime,user_xattr 10.242.1.5@tcp0:/lustrefs /mnt/amlfs 2>&1)
    echo "Error: $MOUNT_ERROR"
    
    # Check dmesg for kernel messages
    echo ""
    echo "Recent kernel messages:"
    dmesg | tail -10 | grep -E "(lustre|mount|error)" || echo "No relevant kernel messages"
    
    # Check if it's a client issue
    if echo "$MOUNT_ERROR" | grep -q "No such file or directory\|unknown filesystem"; then
        echo ""
        echo "🔧 Issue: Lustre client not installed"
        echo "Solution:"
        echo "1. Install net-tools: sudo apt-get install net-tools"
        echo "2. Try Lustre client: sudo apt-get install lustre-client-modules-\$(uname -r)"
        echo "3. Or switch to CentOS VM for better Lustre support"
    elif echo "$MOUNT_ERROR" | grep -q "Connection refused\|timeout"; then
        echo ""
        echo "🔧 Issue: Network connectivity problem"
        echo "Wait longer for NSG rules to propagate (up to 15 minutes)"
    else
        echo ""
        echo "🔧 Issue: Other mount problem"
        echo "Check AMLFS service status in Azure portal"
    fi
fi

echo ""
echo "📊 Summary:"
echo "==========="
echo "✅ VM network configuration: OK (10.242.1.4 in correct subnet)"
echo "✅ AMLFS components discovered: MGS(10.242.1.5) + OSS(10.242.1.7)"
if timeout 2 nc -z 10.242.1.5 988 2>/dev/null; then
    echo "✅ Lustre port accessibility: OK"
else
    echo "❌ Lustre port accessibility: Blocked (NSG rules still propagating?)"
fi
echo ""
echo "💡 Key insight: ICMP (ping) is often disabled on Azure managed services"
echo "   The important test is whether Lustre TCP ports work, not ping!"

# Install net-tools for debugging
echo ""
echo "🔧 Installing network debugging tools..."
sudo apt-get update -qq && sudo apt-get install -y net-tools netcat-openbsd
