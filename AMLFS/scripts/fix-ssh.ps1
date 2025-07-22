# SSH Connection Helper for AMLFS Client VM
# Troubleshoots and fixes common SSH connection issues

param(
    [string]$VmIP = "172.203.149.149",
    [string]$ResourceGroup = "aml-rsj-managed-identity-20250721-1521",
    [string]$VmName = "amlfs-client",
    [string]$Username = "azureuser"
)

Write-Host "🔧 SSH Connection Troubleshooter" -ForegroundColor Green
Write-Host "================================" -ForegroundColor Green
Write-Host "VM IP: $VmIP" -ForegroundColor Yellow
Write-Host "VM Name: $VmName" -ForegroundColor Yellow
Write-Host "Username: $Username" -ForegroundColor Yellow

# Check SSH keys
Write-Host "`n🔍 Step 1: Checking SSH keys..." -ForegroundColor Cyan
$sshKeyPath = "$env:USERPROFILE\.ssh\id_rsa"
$sshPubKeyPath = "$env:USERPROFILE\.ssh\id_rsa.pub"

if (-not (Test-Path $sshKeyPath)) {
    Write-Host "❌ SSH private key not found. Generating new keys..." -ForegroundColor Red
    ssh-keygen -t rsa -b 4096 -f $sshKeyPath -N '""'
    Write-Host "✅ New SSH keys generated" -ForegroundColor Green
}

if (Test-Path $sshPubKeyPath) {
    $publicKey = Get-Content $sshPubKeyPath
    Write-Host "✅ SSH public key found" -ForegroundColor Green
    Write-Host "Key: $($publicKey.Substring(0, 50))..." -ForegroundColor Gray
}

# Step 2: Try different SSH connection methods
Write-Host "`n🔧 Step 2: Trying SSH connections..." -ForegroundColor Cyan

Write-Host "`n   Method 1: Standard SSH..." -ForegroundColor Yellow
try {
    $result = ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$Username@$VmIP" 'echo "Connection successful"' 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Method 1 SUCCESSFUL!" -ForegroundColor Green
        Write-Host "You can connect with: ssh $Username@$VmIP" -ForegroundColor White
        return
    } else {
        Write-Host "❌ Method 1 failed: $result" -ForegroundColor Red
    }
} catch {
    Write-Host "❌ Method 1 failed: $_" -ForegroundColor Red
}

Write-Host "`n   Method 2: Explicit key path..." -ForegroundColor Yellow
try {
    $result = ssh -i $sshKeyPath -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$Username@$VmIP" 'echo "Connection successful"' 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Method 2 SUCCESSFUL!" -ForegroundColor Green
        Write-Host "You can connect with: ssh -i $sshKeyPath $Username@$VmIP" -ForegroundColor White
        return
    } else {
        Write-Host "❌ Method 2 failed: $result" -ForegroundColor Red
    }
} catch {
    Write-Host "❌ Method 2 failed: $_" -ForegroundColor Red
}

# Step 3: Reset VM SSH access
Write-Host "`n🔧 Step 3: Resetting VM SSH access..." -ForegroundColor Cyan
Write-Host "Updating VM with current SSH public key..." -ForegroundColor Yellow

try {
    $publicKey = Get-Content $sshPubKeyPath
    az vm user update --resource-group $ResourceGroup --name $VmName --username $Username --ssh-key-value $publicKey
    Write-Host "✅ SSH key updated on VM" -ForegroundColor Green
    
    Write-Host "`nWaiting 30 seconds for changes to take effect..." -ForegroundColor Yellow
    Start-Sleep -Seconds 30
    
    # Try connecting again
    Write-Host "`n   Method 3: After key reset..." -ForegroundColor Yellow
    $result = ssh -i $sshKeyPath -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$Username@$VmIP" 'echo "Connection successful after reset"' 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Method 3 SUCCESSFUL!" -ForegroundColor Green
        Write-Host "SSH connection fixed! You can now connect with:" -ForegroundColor White
        Write-Host "   ssh $Username@$VmIP" -ForegroundColor Gray
        Write-Host "   OR" -ForegroundColor Gray
        Write-Host "   ssh -i $sshKeyPath $Username@$VmIP" -ForegroundColor Gray
        return
    } else {
        Write-Host "❌ Method 3 failed: $result" -ForegroundColor Red
    }
} catch {
    Write-Host "❌ Failed to update VM SSH key: $_" -ForegroundColor Red
}

# Step 4: Enable password authentication as backup
Write-Host "`n🔧 Step 4: Setting up password authentication as backup..." -ForegroundColor Cyan
$password = "AMLFSClient123!"
Write-Host "Setting password: $password" -ForegroundColor Yellow

try {
    az vm user update --resource-group $ResourceGroup --name $VmName --username $Username --password $password
    Write-Host "✅ Password authentication enabled" -ForegroundColor Green
    Write-Host "`nYou can now connect with password:" -ForegroundColor White
    Write-Host "   ssh $Username@$VmIP" -ForegroundColor Gray
    Write-Host "   (Password: $password)" -ForegroundColor Gray
} catch {
    Write-Host "❌ Failed to set password: $_" -ForegroundColor Red
}

Write-Host "`n📋 SUMMARY - Connection Options:" -ForegroundColor Yellow
Write-Host "1. SSH with key: ssh -i $sshKeyPath $Username@$VmIP" -ForegroundColor White
Write-Host "2. SSH with password: ssh $Username@$VmIP (password: $password)" -ForegroundColor White
Write-Host "3. Azure Serial Console: az serial-console connect --resource-group $ResourceGroup --name $VmName" -ForegroundColor White

Write-Host "`n🔧 Next Steps After SSH Connection:" -ForegroundColor Cyan
Write-Host "1. Install Lustre client: sudo apt-get update && sudo apt-get install lustre-client-modules-`$(uname -r)" -ForegroundColor White
Write-Host "2. Mount AMLFS: See amlfs-mount-info.txt for mount command" -ForegroundColor White
