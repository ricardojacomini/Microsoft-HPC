# Simple HPC Pack DSC Error Fix Script
param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    
    [string]$HeadNodeName = "headnode",
    [string]$DomainName = "hpc.cluster",
    
    [Parameter(Mandatory=$true)]
    [SecureString]$AdminPassword
)

Write-Output "[INFO] Starting HPC Pack DSC error diagnosis and repair..."
Write-Output "[INFO] Resource Group: $ResourceGroupName"
Write-Output "[INFO] Head Node: $HeadNodeName"

# Check if VM exists
try {
    $vm = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $HeadNodeName -ErrorAction Stop
    Write-Output "[SUCCESS] Found VM: $($vm.Name) (Size: $($vm.HardwareProfile.VmSize))"
}
catch {
    Write-Output "[ERROR] VM '$HeadNodeName' not found in resource group '$ResourceGroupName'"
    exit 1
}

# Step 1: Remove failed extensions
Write-Output "[PROGRESS] Removing failed extensions from $HeadNodeName..."
$extensions = Get-AzVMExtension -ResourceGroupName $ResourceGroupName -VMName $HeadNodeName -ErrorAction SilentlyContinue

foreach ($ext in $extensions) {
    if ($ext.ProvisioningState -eq "Failed" -or $ext.Name -like "*setupHpc*") {
        Write-Output "[WARNING] Removing extension: $($ext.Name)"
        try {
            Remove-AzVMExtension -ResourceGroupName $ResourceGroupName -VMName $HeadNodeName -Name $ext.Name -Force -ErrorAction Stop
            Write-Output "[SUCCESS] Successfully removed extension: $($ext.Name)"
        }
        catch {
            Write-Output "[ERROR] Failed to remove extension $($ext.Name): $($_.Exception.Message)"
        }
    }
}

# Step 2: Test domain configuration
Write-Output "[PROGRESS] Testing domain configuration on $HeadNodeName..."
$script = @"
try {
    `$domain = Get-WmiObject -Class Win32_ComputerSystem | Select-Object -ExpandProperty Domain
    if (`$domain -eq '$DomainName') {
        Write-Output 'SUCCESS: VM is joined to domain: ' + `$domain
        return 0
    } else {
        Write-Output 'WARNING: VM domain is ' + `$domain + ', expected $DomainName'
        return 1
    }
}
catch {
    Write-Output 'ERROR: Failed to check domain: ' + `$_.Exception.Message
    return 2
}
"@

try {
    $result = Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroupName -Name $HeadNodeName -CommandId 'RunPowerShellScript' -ScriptString $script -ErrorAction Stop
    Write-Output "[INFO] Domain check result: $($result.Value[0].Message)"
}
catch {
    Write-Output "[ERROR] Failed to run domain check: $($_.Exception.Message)"
}

# Step 3: Install HPC Pack prerequisites
Write-Output "[PROGRESS] Installing HPC Pack prerequisites on $HeadNodeName..."
$prereqScript = @"
# Install required Windows features
Enable-WindowsOptionalFeature -Online -FeatureName IIS-WebServerRole -All -NoRestart
Enable-WindowsOptionalFeature -Online -FeatureName IIS-WebServer -All -NoRestart
Enable-WindowsOptionalFeature -Online -FeatureName IIS-CommonHttpFeatures -All -NoRestart
Enable-WindowsOptionalFeature -Online -FeatureName IIS-NetFxExtensibility45 -All -NoRestart
Enable-WindowsOptionalFeature -Online -FeatureName IIS-ASPNET45 -All -NoRestart

Write-Output 'Prerequisites installation completed'
"@

try {
    $result = Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroupName -Name $HeadNodeName -CommandId 'RunPowerShellScript' -ScriptString $prereqScript -ErrorAction Stop
    Write-Output "[SUCCESS] Prerequisites installation result: $($result.Value[0].Message)"
}
catch {
    Write-Output "[ERROR] Failed to install prerequisites: $($_.Exception.Message)"
}

Write-Output "[SUCCESS] HPC Pack DSC error diagnosis completed!"
Write-Output "[INFO] Next steps:"
Write-Output "[INFO] 1. Wait 5-10 minutes for services to stabilize"
Write-Output "[INFO] 2. Re-run your HPC Pack deployment script"
Write-Output "[INFO] 3. Monitor deployment progress in Azure Portal"
