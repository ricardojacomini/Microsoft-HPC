#!/bin/bash
# AMLFS Complete Network Diagnostic Script

echo "🔧 AMLFS Complete Network Diagnostics"
echo "====================================="
echo "Date: $(date)"
echo "VM IP: $(hostname -I | awk '{print $1}')"
echo "Target: 10.242.1.5"
echo ""

# Wait for NSG rules to propagate
echo "⏳ Waiting 15 seconds for all NSG rules to propagate..."
sleep 15

echo "🔍 1. Basic Network Information"
echo "--------------------------------"
echo "Network interfaces:"
ip addr show | grep -E "(inet 10\.|eth0)"

echo ""
echo "Routing table for 10.242.1.0/24:"
ip route | grep "10.242.1" || echo "No specific route found"

echo ""
echo "Default gateway:"
ip route | grep default

echo ""
echo "🔍 2. Testing Network Connectivity"
echo "----------------------------------"
echo "Testing ping to AMLFS MGS (10.242.1.5)..."

# More verbose ping test
if timeout 10 ping -c 3 -W 3 10.242.1.5; then
    echo "✅ Ping successful!"
    PING_SUCCESS=true
else
    echo "❌ Ping failed"
    PING_SUCCESS=false
    
    echo ""
    echo "Debugging ping failure:"
    echo "- Checking ARP table:"
    arp -a | grep "10.242.1" || echo "  No ARP entries for 10.242.1.x"
    
    echo ""
    echo "- Testing ping to subnet gateway (likely 10.242.1.1):"
    timeout 5 ping -c 2 10.242.1.1 && echo "  ✅ Gateway reachable" || echo "  ❌ Gateway not reachable"
    
    echo ""
    echo "- Testing ping to own IP (loopback test):"
    timeout 5 ping -c 2 $(hostname -I | awk '{print $1}') && echo "  ✅ Self-ping works" || echo "  ❌ Self-ping fails"
fi

echo ""
echo "🔍 3. Firewall and Security Checks"
echo "-----------------------------------"
echo "Local firewall (ufw) status:"
sudo ufw status 2>/dev/null || echo "ufw not active or not installed"

echo ""
echo "iptables rules (if any):"
sudo iptables -L -n | head -20

echo ""
echo "🔍 4. Network Service Tests"
echo "---------------------------"
if [ "$PING_SUCCESS" = true ]; then
    echo "Testing TCP connectivity to Lustre ports on 10.242.1.5:"
    
    for port in 111 988 1023 1024; do
        echo -n "  Port $port: "
        if timeout 5 nc -z 10.242.1.5 $port 2>/dev/null; then
            echo "✅ Open"
        else
            echo "❌ Closed or filtered"
        fi
    done
else
    echo "Skipping port tests - ping failed"
fi

echo ""
echo "🔍 5. DNS and Name Resolution"
echo "-----------------------------"
echo "Testing name resolution:"
echo "  /etc/hosts entries:"
grep -E "(10\.242\.1|amlfs)" /etc/hosts 2>/dev/null || echo "  No relevant entries"

echo ""
echo "  DNS resolution test:"
nslookup 10.242.1.5 2>/dev/null | head -5 || echo "  Reverse lookup failed"

echo ""
echo "🔍 6. AMLFS-Specific Diagnostics"
echo "--------------------------------"
echo "Checking for existing Lustre mounts:"
mount | grep lustre || echo "No Lustre mounts found"

echo ""
echo "Checking for Lustre kernel modules:"
lsmod | grep lustre || echo "No Lustre kernel modules loaded"

echo ""
echo "Checking mount utilities:"
which mount.lustre >/dev/null && echo "✅ mount.lustre found" || echo "❌ mount.lustre not found"

echo ""
echo "🔍 7. Advanced Network Troubleshooting"
echo "--------------------------------------"
if [ "$PING_SUCCESS" = false ]; then
    echo "Testing with different ping parameters:"
    
    echo "  Large packet test:"
    timeout 5 ping -c 1 -s 1472 10.242.1.5 2>/dev/null && echo "  ✅ Large packets work" || echo "  ❌ Large packets fail"
    
    echo "  Different interval test:"
    timeout 5 ping -c 2 -i 0.2 10.242.1.5 2>/dev/null && echo "  ✅ Fast ping works" || echo "  ❌ Fast ping fails"
    
    echo ""
    echo "Network interface statistics:"
    cat /proc/net/dev | grep eth0
    
    echo ""
    echo "System network errors:"
    dmesg | grep -i "network\|eth\|link" | tail -5
fi

echo ""
echo "🔍 8. System Information"
echo "------------------------"
echo "Kernel version: $(uname -r)"
echo "OS version: $(lsb_release -d 2>/dev/null | cut -f2 || cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
echo "Network manager status:"
systemctl is-active NetworkManager 2>/dev/null || echo "NetworkManager not running"
systemctl is-active systemd-networkd 2>/dev/null || echo "systemd-networkd not running"

echo ""
echo "🎯 SUMMARY AND RECOMMENDATIONS"
echo "==============================="
if [ "$PING_SUCCESS" = true ]; then
    echo "✅ Network connectivity to AMLFS is working"
    echo ""
    echo "Next steps:"
    echo "1. Install Lustre client: sudo apt-get install lustre-client-modules-\$(uname -r)"
    echo "2. Create mount point: sudo mkdir -p /mnt/amlfs"
    echo "3. Mount AMLFS: sudo mount -t lustre -o noatime,user_xattr 10.242.1.5@tcp0:/lustrefs /mnt/amlfs"
else
    echo "❌ Network connectivity to AMLFS is NOT working"
    echo ""
    echo "Possible causes and solutions:"
    echo "1. NSG rules haven't propagated yet - wait 5-10 more minutes and retry"
    echo "2. AMLFS service is not responding on 10.242.1.5"
    echo "3. Additional firewall rules on the VM"
    echo "4. Network routing issue in the Azure virtual network"
    echo ""
    echo "Immediate actions:"
    echo "- Wait 10 minutes and run this script again"
    echo "- Check Azure portal for AMLFS health status"
    echo "- Verify NSG rules in Azure portal"
fi
