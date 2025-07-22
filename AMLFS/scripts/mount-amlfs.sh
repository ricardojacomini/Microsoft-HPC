#!/bin/bash

# Azure Lustre File System Mount Script
# Mount Address: 10.242.1.5
# File System Name: lustrefs

echo "Mounting Azure Lustre File System..."

# Create mount point directory
sudo mkdir -p /mnt/amlfs

# Update package list and install NFS utilities (fallback if Lustre client not available)
sudo apt-get update
sudo apt-get install -y nfs-common

# Try to mount using the provided mount command
# Note: If lustre client is not available, this may fail
echo "Attempting Lustre mount..."
sudo mount -t lustre -o noatime,user_xattr 10.242.1.5@tcp0:/lustrefs /mnt/amlfs

if [ $? -eq 0 ]; then
    echo "✅ Successfully mounted AMLFS at /mnt/amlfs"
    echo "Verifying mount:"
    df -h /mnt/amlfs
    ls -la /mnt/amlfs
else
    echo "❌ Lustre mount failed. This is likely due to missing Lustre client packages."
    echo "Possible solutions:"
    echo "1. Install Lustre client for your kernel version"
    echo "2. Use NFS mount as alternative (if AMLFS supports NFS)"
    echo ""
    echo "For Ubuntu 22.04 with kernel 6.8.0-1031-azure, Lustre packages may not be available."
    echo "You may need to compile from source or use alternative access methods."
fi

echo ""
echo "Mount information:"
echo "MGS Address: 10.242.1.5"
echo "File System: lustrefs"
echo "Mount Point: /mnt/amlfs"
echo "Mount Command: mount -t lustre -o noatime,user_xattr,flock 10.242.1.5@tcp0:/lustrefs /mnt/amlfs"
