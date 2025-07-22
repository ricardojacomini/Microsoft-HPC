# Complete AMLFS Mount Guide for SSH Session
# Run these commands in your SSH session in your Linux VM

echo "🚀 AMLFS Client Setup Starting..."

# Step 1: Update system
echo "📦 Updating system packages..."
sudo apt-get update

# Step 2: Install Lustre client (try multiple methods)
echo "🔧 Installing Lustre client..."

# Method 1: Try generic lustre-client
sudo apt-get install -y lustre-client
if [ $? -eq 0 ]; then
    echo "✅ Method 1 successful: lustre-client installed"
else
    echo "⚠️ Method 1 failed, trying Method 2..."
    
    # Method 2: Enable universe repo and install lustre-utils
    sudo apt-get install -y software-properties-common
    sudo add-apt-repository universe -y
    sudo apt-get update
    sudo apt-get install -y lustre-utils
    
    if [ $? -eq 0 ]; then
        echo "✅ Method 2 successful: lustre-utils installed"
    else
        echo "⚠️ Method 2 failed, trying Method 3..."
        
        # Method 3: Install from specific Ubuntu packages
        sudo apt-get install -y lustre-client-modules-$(uname -r | cut -d'-' -f1-2)-generic
        
        if [ $? -ne 0 ]; then
            echo "⚠️ All methods failed. Installing minimal lustre utilities..."
            sudo apt-get install -y lustre-dev lustre-utils
        fi
    fi
fi

# Step 3: Verify Lustre installation
echo "🔍 Verifying Lustre installation..."
which lfs
if [ $? -eq 0 ]; then
    lfs --version
    echo "✅ Lustre command-line tools available"
else
    echo "❌ Lustre tools not found"
fi

# Step 4: Check/load Lustre kernel modules
echo "🔍 Checking Lustre kernel modules..."
sudo modprobe lustre 2>/dev/null
if [ $? -eq 0 ]; then
    echo "✅ Lustre kernel modules loaded successfully"
    lsmod | grep lustre
else
    echo "⚠️ Lustre kernel modules not available (this might be OK for client-only access)"
fi

# Step 5: Create mount point
echo "📁 Creating AMLFS mount point..."
sudo mkdir -p /mnt/amlfs
sudo chown azureuser:azureuser /mnt/amlfs

# Step 6: Mount AMLFS
echo "🔗 Mounting AMLFS..."
# You'll need to replace <MOUNT_ADDRESS> with the actual mount address
# Get it from the PowerShell session by running: .\next-steps.ps1

echo "📋 MOUNT COMMAND (replace <MOUNT_ADDRESS> with actual address):"
echo "sudo mount -t lustre <MOUNT_ADDRESS>/lustrefs /mnt/amlfs"
echo ""
echo "Example:"
echo "sudo mount -t lustre -o noatime,user_xattr,flock 10.242.1.4@tcp:/lustrefs /mnt/amlfs"
echo ""

# Step 7: Verification commands
echo "🔍 After mounting, run these commands to verify:"
echo "df -h /mnt/amlfs"
echo "ls -la /mnt/amlfs"
echo "touch /mnt/amlfs/test-file.txt"
echo "echo 'Hello AMLFS!' > /mnt/amlfs/test-file.txt"
echo "cat /mnt/amlfs/test-file.txt"

echo ""
echo "🎉 Setup complete! Use the mount command above with your actual AMLFS address."
