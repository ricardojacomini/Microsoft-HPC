# Direct domain controller setup script
# This bypasses the DSC extension issues and directly promotes the domain controller

$resourceGroupName = "jacomini-hpcpack-hseries-ib-eastus"
$vmName = "headnodedc"
$domainName = "hpc.cluster"
$adminUsername = "hpcadmin"
$adminPassword = "P@ssw0rd123!"

# Script to run on the VM for domain controller promotion
$dcPromotionScript = @"
# Install AD DS role
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools

# Import AD DS module
Import-Module ADDSDeployment

# Create secure string for password
`$SecurePassword = ConvertTo-SecureString '$adminPassword' -AsPlainText -Force

# Promote to domain controller
Install-ADDSForest ``
    -DomainName '$domainName' ``
    -SafeModeAdministratorPassword `$SecurePassword ``
    -DomainMode 'WinThreshold' ``
    -ForestMode 'WinThreshold' ``
    -DatabasePath 'F:\NTDS' ``
    -LogPath 'F:\NTDS' ``
    -SysvolPath 'F:\SYSVOL' ``
    -InstallDns ``
    -NoRebootOnCompletion ``
    -Force

Write-Host "Domain controller promotion completed. Rebooting..."
Restart-Computer -Force
"@

Write-Host "Verifying F: drive is available..."
$driveCheck = Invoke-AzVMRunCommand -ResourceGroupName $resourceGroupName -VMName $vmName -CommandId "RunPowerShellScript" -ScriptString "Get-Volume | Where-Object DriveLetter -eq 'F' | Select-Object DriveLetter, FileSystemLabel, Size, SizeRemaining"

if ($driveCheck.Value[0].Message -match "F.*") {
    Write-Host "F: drive confirmed available. Proceeding with domain controller promotion..."
    
    # Execute the domain controller promotion script
    Write-Host "Promoting domain controller..."
    $result = Invoke-AzVMRunCommand -ResourceGroupName $resourceGroupName -VMName $vmName -CommandId "RunPowerShellScript" -ScriptString $dcPromotionScript
    
    Write-Host "Domain controller promotion script executed. Result:"
    $result.Value | ForEach-Object { Write-Host $_.Message }
    
    # Wait for reboot and check status
    Write-Host "Waiting for VM to reboot and complete domain controller setup..."
    Start-Sleep -Seconds 120
    
    # Check domain controller status
    $statusCheck = Invoke-AzVMRunCommand -ResourceGroupName $resourceGroupName -VMName $vmName -CommandId "RunPowerShellScript" -ScriptString "Get-ADDomain -ErrorAction SilentlyContinue | Select-Object DNSRoot, DomainMode"
    
    Write-Host "Domain status check:"
    $statusCheck.Value | ForEach-Object { Write-Host $_.Message }
} else {
    Write-Host "ERROR: F: drive not available. Please ensure the data disk is properly mounted."
}
