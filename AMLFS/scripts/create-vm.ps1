# VM Creation Helper Script for AMLFS Client
# Handles common capacity and availability issues

param(
    [string]$ResourceGroup = "aml-rsj-managed-identity-20250721-1521",
    [string]$VmName = "amlfs-client",
    [string]$VnetName = "vnet",
    [string]$SubnetName = "amlfs"
)

Write-Host "🚀 AMLFS Client VM Creation Helper" -ForegroundColor Green
Write-Host "=================================" -ForegroundColor Green

# Clear cache first
Write-Host "🧹 Clearing Azure CLI cache..." -ForegroundColor Yellow
az cache purge

# VM size options (in order of preference)
$vmSizes = @("Standard_B2s", "Standard_D2s_v3", "Standard_B1s", "Standard_A1_v2")
$zones = @("", "1", "2", "3")  # Empty string means no zone specified

Write-Host "🔍 Attempting VM creation with different sizes and zones..." -ForegroundColor Cyan

foreach ($size in $vmSizes) {
    foreach ($zone in $zones) {
        $zoneParam = if ($zone) { "--zone $zone" } else { "" }
        $displayZone = if ($zone) { " in Zone $zone" } else { " (no zone specified)" }
        
        Write-Host "`n⏳ Trying $size$displayZone..." -ForegroundColor Yellow
        
        $command = "az vm create --resource-group `"$ResourceGroup`" --name `"$VmName`" --image `"Ubuntu2204`" --size `"$size`" --vnet-name `"$VnetName`" --subnet `"$SubnetName`" --generate-ssh-keys --public-ip-sku Standard $zoneParam --no-wait"
        
        try {
            Invoke-Expression $command
            
            # Wait a moment and check if VM was created
            Start-Sleep -Seconds 15
            $vmState = az vm show --resource-group $ResourceGroup --name $VmName --query "provisioningState" -o tsv 2>$null
            
            if ($vmState -eq "Succeeded" -or $vmState -eq "Creating") {
                Write-Host "✅ SUCCESS! VM creation started with $size$displayZone" -ForegroundColor Green
                
                # Wait for completion
                Write-Host "⏳ Waiting for VM to be fully provisioned..." -ForegroundColor Yellow
                do {
                    Start-Sleep -Seconds 30
                    $vmState = az vm show --resource-group $ResourceGroup --name $VmName --query "provisioningState" -o tsv 2>$null
                    Write-Host "   Status: $vmState" -ForegroundColor Gray
                } while ($vmState -eq "Creating")
                
                if ($vmState -eq "Succeeded") {
                    # Get public IP
                    $publicIp = az vm show --resource-group $ResourceGroup --name $VmName --show-details --query "publicIps" -o tsv
                    
                    Write-Host "`n🎉 VM CREATED SUCCESSFULLY!" -ForegroundColor Green
                    Write-Host "📊 VM Details:" -ForegroundColor Cyan
                    Write-Host "   Name: $VmName" -ForegroundColor White
                    Write-Host "   Size: $size" -ForegroundColor White
                    Write-Host "   Zone: $(if($zone){"$zone"}else{"Default"})" -ForegroundColor White
                    Write-Host "   Public IP: $publicIp" -ForegroundColor White
                    Write-Host "`n📋 SSH Command:" -ForegroundColor Yellow
                    Write-Host "   ssh azureuser@$publicIp" -ForegroundColor White
                    
                    Write-Host "`n🔧 Next Steps:" -ForegroundColor Cyan
                    Write-Host "1. SSH to the VM using the command above" -ForegroundColor White
                    Write-Host "2. Follow the Lustre client installation steps from README-managed-identity.md Step 3" -ForegroundColor White
                    Write-Host "3. Quick install: Run the automated script below" -ForegroundColor White
                    
                    # Save VM info with updated instructions
                    @"
# AMLFS Client VM Information
VM_NAME=$VmName
VM_SIZE=$size
VM_ZONE=$(if($zone){"$zone"}else{"Default"})
PUBLIC_IP=$publicIp
RESOURCE_GROUP=$ResourceGroup

# SSH Command:
ssh azureuser@$publicIp

# Next steps after SSH:
# 1. Download and run the Lustre installation script:
wget https://raw.githubusercontent.com/your-repo/amlfs-setup/main/install-lustre-ubuntu.sh
chmod +x install-lustre-ubuntu.sh
sudo ./install-lustre-ubuntu.sh

# OR follow manual steps from README-managed-identity.md Step 3:
# Step 3.1: Install Compatible Kernel
sudo apt update
sudo apt install -y linux-image-azure-lts-24.04
sudo apt remove -y linux-image-azure

# Step 3.2: Configure Repository  
cat <<'EOF' > /tmp/setup-amlfs-repo.sh
#!/bin/bash
set -euo pipefail
apt update
apt install -y ca-certificates curl apt-transport-https lsb-release gnupg
source /etc/lsb-release
echo "deb [arch=amd64] https://packages.microsoft.com/repos/amlfs-\${DISTRIB_CODENAME}/ \${DISTRIB_CODENAME} main" | tee /etc/apt/sources.list.d/amlfs.list
curl -sL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | tee /etc/apt/trusted.gpg.d/microsoft.gpg > /dev/null
apt update
EOF
chmod +x /tmp/setup-amlfs-repo.sh
sudo bash /tmp/setup-amlfs-repo.sh

# Step 3.3-3.4: Install Kernel and Configure Boot
sudo apt full-upgrade -y
sudo apt install -y linux-image-6.8.0-1030-azure
sudo sed -i 's/GRUB_DEFAULT=.*/GRUB_DEFAULT="1>2"/' /etc/default/grub
sudo update-grub
sudo reboot

# After reboot, continue with Step 3.5:
sudo apt-get install -y amlfs-lustre-client-2.16.1-14-gbc76088=\$(uname -r)
sudo apt-get install -f -y
sudo modprobe lnet
sudo modprobe lustre
lsmod | grep -E "(lustre|lnet)"

# Mount AMLFS (Step 5 from README):
mkdir /amlfs-prod-20250721-152206
sudo mount -t lustre -o noatime,user_xattr,flock 10.242.1.5@tcp0:/lustrefs /amlfs-prod-20250721-152206
"@ | Out-File -FilePath "vm-info.txt" -Encoding UTF8
# 1. SSH to VM
# 2. Install Lustre: Follow README-managed-identity.md Step 3 (complete kernel setup required)
# 3. Mount AMLFS: mkdir /amlfs-prod-20250721-152206 && sudo mount -t lustre -o noatime,user_xattr,flock 10.242.1.5@tcp0:/lustrefs /amlfs-prod-20250721-152206
"@ | Out-File -FilePath "vm-info.txt" -Encoding UTF8
                    
                    Write-Host "`n💾 VM information saved to: vm-info.txt" -ForegroundColor Green
                    exit 0
                } else {
                    Write-Host "❌ VM creation failed with state: $vmState" -ForegroundColor Red
                }
            }
        }
        catch {
            Write-Host "❌ Failed: $_" -ForegroundColor Red
        }
        
        # Clean up failed attempt
        Write-Host "🧹 Cleaning up failed attempt..." -ForegroundColor Gray
        az vm delete --resource-group $ResourceGroup --name $VmName --yes --no-wait 2>$null
        Start-Sleep -Seconds 5
    }
}

Write-Host "`n❌ All VM creation attempts failed!" -ForegroundColor Red
Write-Host "🔍 Troubleshooting suggestions:" -ForegroundColor Yellow
Write-Host "1. Check quota: az vm list-usage --location eastus -o table" -ForegroundColor White
Write-Host "2. Try different region: --location westus2" -ForegroundColor White
Write-Host "3. Contact Azure support for capacity issues" -ForegroundColor White
