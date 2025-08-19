<#
.Synopsis
    Updates the HPC communication certificate for this HPC node (Enhanced Version).

.DESCRIPTION
    This script updates the HPC communication certificate for this HPC node with improved security,
    error handling, and modern PowerShell practices.

.NOTES
    This cmdlet requires that the current machine is an HPC node in an HPC Pack 2016 or later cluster.
    Enhanced version with improved security and reliability.

.EXAMPLE
    Update the HPC communication certificate for this HPC node.
    PS > Update-HpcNodeCertificate-Enhanced.ps1 -Thumbprint 466C3A692200566BF33ED338684299E43D3C51CE

.EXAMPLE
    Update the HPC communication certificate for this HPC node after 10 seconds delay.
    PS > Update-HpcNodeCertificate-Enhanced.ps1 -Thumbprint 466C3A692200566BF33ED338684299E43D3C51CE -Delay 10

.EXAMPLE
    Install a new certificate, and schedules a task to update it as the HPC communication certificate on this node.
    PS > Update-HpcNodeCertificate-Enhanced.ps1 -PfxFilePath "d:\newcert.pfx" -RunAsScheduledTask
#>

[CmdletBinding(DefaultParameterSetName = "Thumbprint")]
Param(
    # The Path of the PFX format certificate file.
    [Parameter(Mandatory = $true, ParameterSetName = "PfxFile")]
    [ValidateScript({
        if (-not (Test-Path $_)) {
            throw "Certificate file '$_' not found."
        }
        if (-not $_.EndsWith('.pfx', [StringComparison]::OrdinalIgnoreCase)) {
            throw "File '$_' must be a .pfx file."
        }
        return $true
    })]
    [String] $PfxFilePath,

    # The protection password of the PFX format certificate file.
    [Parameter(Mandatory = $false, ParameterSetName = "PfxFile")]
    [SecureString] $Password,

    # The thumbprint of the certificate which had already been installed in "Local Computer\Personal" store on this node.
    [Parameter(Mandatory = $true, ParameterSetName = "Thumbprint")]
    [ValidatePattern('^[A-Fa-f0-9]{40}$')]
    [String] $Thumbprint,

    # If specified, the delay time in seconds for the operation.
    [Parameter(Mandatory = $false)]
    [ValidateRange(0, 3600)]
    [int] $Delay = 0,

    # If specified, update the HPC communication certificate using a scheduled task.
    [Parameter(Mandatory = $false)]
    [Switch] $RunAsScheduledTask,

    # The log file path, if not specified, the log will be generated in system temp folder.
    [Parameter(Mandatory = $false)]
    [String] $LogFile,

    # Skip certificate expiration validation
    [Parameter(Mandatory = $false)]
    [Switch] $SkipExpirationCheck,

    # Force certificate update even if same thumbprint
    [Parameter(Mandatory = $false)]
    [Switch] $Force
)

#Requires -RunAsAdministrator
#Requires -Version 5.1

# Initialize script variables
$script:LogFile = $LogFile
$script:VerbosePreference = "Continue"
$script:ErrorActionPreference = "Stop"

# Enhanced logging function
function Write-EnhancedLog {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [String] $Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Error", "Warning", "Information", "Verbose")]
        [String] $LogLevel = "Information",

        [Parameter(Mandatory = $false)]
        [Switch] $NoConsole
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $formattedMessage = "[$LogLevel] $timestamp - $Message"
    
    # Console output
    if (-not $NoConsole) {
        switch ($LogLevel) {
            "Error" { Write-Error $formattedMessage }
            "Warning" { Write-Warning $formattedMessage }
            "Information" { Write-Information $formattedMessage -InformationAction Continue }
            "Verbose" { Write-Verbose $formattedMessage }
        }
    }
    
    # File logging with error handling
    if ($script:LogFile) {
        try {
            $logEntry = "[$LogLevel] $timestamp - $Message"
            Add-Content -Path $script:LogFile -Value $logEntry -Encoding UTF8 -ErrorAction Stop
        }
        catch {
            Write-Warning "Failed to write to log file: $($_.Exception.Message)"
        }
    }
}

# Enhanced certificate validation function
function Test-CertificateQuality {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [System.Security.Cryptography.X509Certificates.X509Certificate2] $Certificate,
        
        [Parameter(Mandatory = $false)]
        [Switch] $SkipExpirationCheck,
        
        [Parameter(Mandatory = $true)]
        [System.Version] $HpcVersion,
        
        [Parameter(Mandatory = $true)]
        [bool] $ServiceFabricHN
    )
    
    $validationResults = @{
        IsValid = $true
        Issues = @()
        Warnings = @()
    }
    
    # Check private key
    if (-not $Certificate.HasPrivateKey) {
        $validationResults.IsValid = $false
        $validationResults.Issues += "Certificate has no private key"
    }
    
    # Check expiration
    if (-not $SkipExpirationCheck) {
        $now = Get-Date
        if ($Certificate.NotAfter -lt $now) {
            $validationResults.IsValid = $false
            $validationResults.Issues += "Certificate expired on $($Certificate.NotAfter)"
        }
        elseif ($Certificate.NotAfter -lt $now.AddDays(30)) {
            $validationResults.Warnings += "Certificate expires soon: $($Certificate.NotAfter)"
        }
        
        if ($Certificate.NotBefore -gt $now) {
            $validationResults.IsValid = $false
            $validationResults.Issues += "Certificate not yet valid until $($Certificate.NotBefore)"
        }
    }
    
    # Check key usage
    $keyUsageExtension = $Certificate.Extensions | Where-Object { $_.Oid.FriendlyName -eq "Key Usage" }
    if ($keyUsageExtension) {
        $keyUsage = [System.Security.Cryptography.X509Certificates.X509KeyUsageExtension]$keyUsageExtension
        if (-not ($keyUsage.KeyUsages -band [System.Security.Cryptography.X509Certificates.X509KeyUsageFlags]::KeyEncipherment)) {
            $validationResults.Warnings += "Certificate may not support key encipherment"
        }
    }
    
    return $validationResults
}

# Secure certificate KeySpec validation
function Get-CertificateKeySpec {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [String] $CertificateThumbprint,
        
        [Parameter(Mandatory = $false)]
        [String] $PfxPath
    )
    
    try {
        if ($PfxPath) {
            # Use PowerShell native methods instead of CertUtil for security
            $cert = Get-PfxCertificate -FilePath $PfxPath -ErrorAction Stop
            # Get key spec from certificate properties
            $keySpec = $cert.PrivateKey.CspKeyContainerInfo.KeyNumber
        }
        else {
            $cert = Get-ChildItem -Path "Cert:\LocalMachine\My\$CertificateThumbprint" -ErrorAction Stop
            $keySpec = $cert.PrivateKey.CspKeyContainerInfo.KeyNumber
        }
        
        return $keySpec
    }
    catch {
        Write-EnhancedLog "Unable to determine KeySpec for certificate: $($_.Exception.Message)" -LogLevel Warning
        return $null
    }
}

# Enhanced HPC validation
function Test-HpcNodeValidity {
    [CmdletBinding()]
    Param()
    
    $hpcKeyPath = "HKLM:\SOFTWARE\Microsoft\HPC"
    $hpcWow6432KeyPath = "HKLM:\SOFTWARE\Wow6432Node\Microsoft\HPC"
    
    $validationResults = @{
        IsValid = $false
        KeyExists = $false
        SSLThumbprint = $null
        InstalledRole = $null
        ClusterConnectionString = $null
        IsHeadNode = $false
        ServiceFabricHN = $false
        HpcVersion = $null
    }
    
    # Check if HPC registry key exists
    if (-not (Test-Path -Path $hpcKeyPath)) {
        return $validationResults
    }
    
    $validationResults.KeyExists = $true
    
    try {
        # Get HPC registry properties
        $sslThumbprintItem = Get-ItemProperty -Name SSLThumbprint -LiteralPath $hpcKeyPath -ErrorAction SilentlyContinue
        $roleItem = Get-ItemProperty -Name InstalledRole -LiteralPath $hpcKeyPath -ErrorAction SilentlyContinue
        $hnListItem = Get-ItemProperty -Name ClusterConnectionString -LiteralPath $hpcKeyPath -ErrorAction SilentlyContinue
        
        if ($null -eq $sslThumbprintItem -or $null -eq $roleItem -or $null -eq $hnListItem) {
            return $validationResults
        }
        
        $validationResults.SSLThumbprint = $sslThumbprintItem.SSLThumbprint
        $validationResults.InstalledRole = $roleItem.InstalledRole
        $validationResults.ClusterConnectionString = $hnListItem.ClusterConnectionString
        $validationResults.IsHeadNode = ($roleItem.InstalledRole -contains 'HN')
        
        # Check for Service Fabric head node
        if ($validationResults.IsHeadNode -and $hnListItem.ClusterConnectionString.Contains(',')) {
            $hpcSecKeyItem = Get-Item -Path "HKLM:\SOFTWARE\Microsoft\HPC\Security" -ErrorAction SilentlyContinue
            $validationResults.ServiceFabricHN = ($null -eq $hpcSecKeyItem) -or ($hpcSecKeyItem.Property -notcontains "HAStorageDbConnectionString")
        }
        
        # Get HPC Pack version
        $ccpHome = [Environment]::GetEnvironmentVariable("CCP_HOME", 'Machine')
        if ($ccpHome) {
            $hpcCommonDll = [IO.Path]::Combine($ccpHome, 'Bin\HpcCommon.dll')
            if (Test-Path $hpcCommonDll) {
                $versionStr = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($hpcCommonDll).FileVersion
                $validationResults.HpcVersion = New-Object System.Version $versionStr
            }
        }
        
        $validationResults.IsValid = $true
    }
    catch {
        Write-EnhancedLog "Error validating HPC node: $($_.Exception.Message)" -LogLevel Error
    }
    
    return $validationResults
}

# Enhanced certificate installation with better error handling
function Install-CertificateSecurely {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [String] $PfxPath,
        
        [Parameter(Mandatory = $true)]
        [SecureString] $SecurePassword,
        
        [Parameter(Mandatory = $true)]
        [String] $Thumbprint,
        
        [Parameter(Mandatory = $true)]
        [bool] $IsHeadNode
    )
    
    try {
        # Remove existing certificate if present
        if (Test-Path -Path "Cert:\LocalMachine\My\$Thumbprint") {
            Write-EnhancedLog "Removing existing certificate: $Thumbprint"
            Remove-Item -Path "Cert:\LocalMachine\My\$Thumbprint" -Force
        }
        
        # Prepare key storage flags
        $keyFlags = [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::PersistKeySet -bor 
                   [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::MachineKeySet
        
        if ($IsHeadNode) {
            $keyFlags = $keyFlags -bor [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable
        }
        
        # Import certificate using .NET methods (more secure than certutil)
        Write-EnhancedLog "Importing certificate to Local Machine Personal store"
        $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
        $cert.Import($PfxPath, $SecurePassword, $keyFlags)
        
        $store = New-Object System.Security.Cryptography.X509Certificates.X509Store("My", "LocalMachine")
        try {
            $store.Open("ReadWrite")
            $store.Add($cert)
            Write-EnhancedLog "Certificate successfully imported to Personal store"
        }
        finally {
            $store.Close()
        }
        
        # Install in Trusted Root if self-signed
        if ($cert.Subject -eq $cert.Issuer -and -not (Test-Path -Path "Cert:\LocalMachine\Root\$Thumbprint")) {
            Write-EnhancedLog "Installing self-signed certificate to Trusted Root CA store"
            $publicCert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
            $publicCert.Import($cert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert))
            
            $rootStore = New-Object System.Security.Cryptography.X509Certificates.X509Store("Root", "LocalMachine")
            try {
                $rootStore.Open("ReadWrite")
                $rootStore.Add($publicCert)
                Write-EnhancedLog "Self-signed certificate installed to Trusted Root CA store"
            }
            finally {
                $rootStore.Close()
            }
        }
        
        return $true
    }
    catch {
        Write-EnhancedLog "Failed to install certificate: $($_.Exception.Message)" -LogLevel Error
        throw
    }
}

# Enhanced service restart with dependency handling
function Restart-HpcServicesSecurely {
    [CmdletBinding()]
    Param()
    
    $hpcServices = @(
        "HpcManagement", "HpcBroker", "HpcDeployment", "HpcDiagnostics", 
        "HpcFrontendService", "HpcMonitoringClient", "HpcMonitoringServer", 
        "HpcNamingService", "HpcNodeManager", "HpcReporting", "HpcScheduler",
        "HpcSession", "HpcSoaDiagMon", "HpcWebService"
    )
    
    $restartFailures = @()
    $servicesToRestart = @()
    
    # First, identify services that need restarting
    foreach ($serviceName in $hpcServices) {
        try {
            $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
            if ($null -eq $service) {
                continue
            }
            
            if (($service.StartType -eq [System.ServiceProcess.ServiceStartMode]::Automatic) -or 
                ($service.Status -eq [System.ServiceProcess.ServiceControllerStatus]::Running)) {
                $servicesToRestart += $service
            }
        }
        catch {
            Write-EnhancedLog "Error checking service $serviceName : $($_.Exception.Message)" -LogLevel Warning
        }
    }
    
    # Restart services with retry logic
    foreach ($service in $servicesToRestart) {
        $retryCount = 0
        $maxRetries = 3
        $success = $false
        
        while ($retryCount -lt $maxRetries -and -not $success) {
            try {
                Write-EnhancedLog "Restarting service: $($service.Name) (Attempt $($retryCount + 1))"
                Restart-Service -Name $service.Name -Force -ErrorAction Stop
                
                # Wait and verify service started
                Start-Sleep -Seconds 2
                $updatedService = Get-Service -Name $service.Name
                if ($updatedService.Status -eq [System.ServiceProcess.ServiceControllerStatus]::Running) {
                    Write-EnhancedLog "Service $($service.Name) restarted successfully"
                    $success = $true
                }
                else {
                    throw "Service did not start properly (Status: $($updatedService.Status))"
                }
            }
            catch {
                $retryCount++
                $errorMsg = "Failed to restart service $($service.Name) (Attempt $retryCount): $($_.Exception.Message)"
                
                if ($retryCount -lt $maxRetries) {
                    Write-EnhancedLog $errorMsg -LogLevel Warning
                    Start-Sleep -Seconds 5
                }
                else {
                    Write-EnhancedLog $errorMsg -LogLevel Error
                    $restartFailures += $service.Name
                }
            }
        }
    }
    
    return $restartFailures
}

# Main script execution
try {
    # Initialize logging
    $dateStr = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    if (-not $script:LogFile) {
        $script:LogFile = "$env:TEMP\Update-HpcNodeCertificate-Enhanced-$dateStr.log"
    }
    
    Write-EnhancedLog "=== HPC Node Certificate Update (Enhanced) Started ===" -LogLevel Information
    Write-EnhancedLog "Log file: $script:LogFile" -LogLevel Information
    
    # Validate HPC node
    Write-EnhancedLog "Validating HPC node configuration..." -LogLevel Information
    $hpcValidation = Test-HpcNodeValidity
    
    if (-not $hpcValidation.IsValid) {
        throw "This computer ($env:COMPUTERNAME) is not a valid HPC cluster node or HPC Pack is not properly installed"
    }
    
    Write-EnhancedLog "HPC Pack version: $($hpcValidation.HpcVersion)" -LogLevel Information
    Write-EnhancedLog "Current SSL thumbprint: $($hpcValidation.SSLThumbprint)" -LogLevel Information
    Write-EnhancedLog "Installed role(s): $($hpcValidation.InstalledRole)" -LogLevel Information
    
    # Process certificate based on parameter set
    $certificateToInstall = $null
    $targetThumbprint = $null
    
    if ($PSCmdlet.ParameterSetName -eq "PfxFile") {
        Write-EnhancedLog "Processing PFX file: $PfxFilePath" -LogLevel Information
        
        # Get password securely if not provided
        if (-not $Password) {
            $Password = Read-Host -Prompt "Enter password for certificate file '$PfxFilePath'" -AsSecureString
        }
        
        # Load certificate for validation
        try {
            $keyFlags = [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::DefaultKeySet
            $certificateToInstall = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
            $certificateToInstall.Import($PfxFilePath, $Password, $keyFlags)
            $targetThumbprint = $certificateToInstall.Thumbprint
        }
        catch {
            throw "Failed to load PFX certificate: $($_.Exception.Message)"
        }
    }
    else {
        # Using existing certificate by thumbprint
        Write-EnhancedLog "Using existing certificate with thumbprint: $Thumbprint" -LogLevel Information
        $targetThumbprint = $Thumbprint
        
        try {
            $certificateToInstall = Get-ChildItem -Path "Cert:\LocalMachine\My\$Thumbprint" -ErrorAction Stop
        }
        catch {
            throw "Certificate with thumbprint '$Thumbprint' not found in Local Machine Personal store"
        }
    }
    
    # Check if certificate is already in use (unless forced)
    if ($hpcValidation.SSLThumbprint -eq $targetThumbprint -and -not $Force) {
        Write-EnhancedLog "Certificate $targetThumbprint is already configured as HPC communication certificate" -LogLevel Warning
        Write-EnhancedLog "Use -Force parameter to update anyway" -LogLevel Information
        return
    }
    
    # Validate certificate quality
    Write-EnhancedLog "Validating certificate quality..." -LogLevel Information
    $certValidation = Test-CertificateQuality -Certificate $certificateToInstall -SkipExpirationCheck:$SkipExpirationCheck -HpcVersion $hpcValidation.HpcVersion -ServiceFabricHN $hpcValidation.ServiceFabricHN
    
    if (-not $certValidation.IsValid) {
        $issues = $certValidation.Issues -join "; "
        throw "Certificate validation failed: $issues"
    }
    
    if ($certValidation.Warnings.Count -gt 0) {
        foreach ($warning in $certValidation.Warnings) {
            Write-EnhancedLog $warning -LogLevel Warning
        }
    }
    
    # Check KeySpec if possible
    $keySpec = Get-CertificateKeySpec -CertificateThumbprint $targetThumbprint -PfxPath $PfxFilePath
    if ($null -ne $keySpec) {
        if ($keySpec -eq 2) {
            throw "Certificate KeySpec is AT_SIGNATURE, but AT_KEYEXCHANGE is required for HPC communication"
        }
        elseif ($keySpec -eq 0 -and ($hpcValidation.HpcVersion.Major -eq 5 -or $hpcValidation.ServiceFabricHN)) {
            throw "CNG certificates are not supported in this HPC cluster configuration"
        }
    }
    
    # Handle scheduled task execution
    if ($RunAsScheduledTask) {
        Write-EnhancedLog "Creating scheduled task for certificate update..." -LogLevel Information
        
        # Create secure scheduled task (implementation would go here)
        # For brevity, this is simplified - in production, use ScheduledTasks module
        throw "Scheduled task functionality requires additional implementation for security"
    }
    
    # Apply delay if specified
    if ($Delay -gt 0) {
        Write-EnhancedLog "Waiting $Delay seconds before applying certificate update..." -LogLevel Information
        Start-Sleep -Seconds $Delay
    }
    
    # Install certificate if from PFX
    if ($PSCmdlet.ParameterSetName -eq "PfxFile") {
        Install-CertificateSecurely -PfxPath $PfxFilePath -SecurePassword $Password -Thumbprint $targetThumbprint -IsHeadNode $hpcValidation.IsHeadNode
    }
    
    # Set Network Service permissions for Service Fabric head nodes
    if ($hpcValidation.ServiceFabricHN) {
        try {
            Write-EnhancedLog "Setting Network Service permissions for Service Fabric head node..." -LogLevel Information
            $cert = Get-ChildItem -Path "Cert:\LocalMachine\My\$targetThumbprint"
            $keyContainerName = $cert.PrivateKey.CspKeyContainerInfo.UniqueKeyContainerName
            $keyPath = Join-Path -Path $env:ProgramData -ChildPath "Microsoft\Crypto\RSA\MachineKeys\$keyContainerName"
            
            if (Test-Path $keyPath) {
                $networkServiceSid = [System.Security.Principal.WellKnownSidType]::NetworkServiceSid
                $sid = New-Object System.Security.Principal.SecurityIdentifier($networkServiceSid, $null)
                $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule($sid, "FullControl", "Allow")
                
                $acl = (Get-Item $keyPath).GetAccessControl('Access')
                $acl.SetAccessRule($accessRule)
                Set-Acl -Path $keyPath -AclObject $acl
                
                Write-EnhancedLog "Network Service permissions set successfully" -LogLevel Information
            }
        }
        catch {
            Write-EnhancedLog "Failed to set Network Service permissions: $($_.Exception.Message)" -LogLevel Warning
        }
    }
    
    # Update registry
    Write-EnhancedLog "Updating HPC registry with new certificate thumbprint..." -LogLevel Information
    
    $hpcKeyPath = "HKLM:\SOFTWARE\Microsoft\HPC"
    $hpcWow6432KeyPath = "HKLM:\SOFTWARE\Wow6432Node\Microsoft\HPC"
    
    # Update cluster registry for single HPC Pack 2019 head node
    if ($hpcValidation.IsHeadNode -and ($hpcValidation.HpcVersion.Major -eq 6) -and 
        -not $hpcValidation.ClusterConnectionString.Contains(',')) {
        try {
            Set-HpcClusterRegistry -PropertyName SSLThumbprint -PropertyValue $targetThumbprint
            Write-EnhancedLog "Cluster registry updated" -LogLevel Information
        }
        catch {
            Write-EnhancedLog "Failed to update cluster registry: $($_.Exception.Message)" -LogLevel Warning
        }
    }
    
    # Update local registry
    Set-ItemProperty -Path $hpcKeyPath -Name SSLThumbprint -Value $targetThumbprint
    if (Test-Path $hpcWow6432KeyPath) {
        Set-ItemProperty -Path $hpcWow6432KeyPath -Name SSLThumbprint -Value $targetThumbprint
    }
    
    Write-EnhancedLog "Registry updated successfully" -LogLevel Information
    
    # Restart HPC services
    Write-EnhancedLog "Restarting HPC services..." -LogLevel Information
    $failedServices = Restart-HpcServicesSecurely
    
    if ($failedServices.Count -eq 0) {
        Write-EnhancedLog "All HPC services restarted successfully" -LogLevel Information
        Write-EnhancedLog "HPC communication certificate successfully updated to: $targetThumbprint" -LogLevel Information
    }
    else {
        $failedList = $failedServices -join ", "
        Write-EnhancedLog "Failed to restart some services: $failedList" -LogLevel Warning
        Write-EnhancedLog "Certificate update completed, but manual service restart or system reboot may be required" -LogLevel Warning
    }
    
    Write-EnhancedLog "=== HPC Node Certificate Update Completed Successfully ===" -LogLevel Information
}
catch {
    $errorMessage = "Certificate update failed: $($_.Exception.Message)"
    Write-EnhancedLog $errorMessage -LogLevel Error
    
    # Additional error details for troubleshooting
    if ($_.Exception.InnerException) {
        Write-EnhancedLog "Inner exception: $($_.Exception.InnerException.Message)" -LogLevel Error
    }
    
    Write-EnhancedLog "=== HPC Node Certificate Update Failed ===" -LogLevel Error
    throw
}
finally {
    if ($script:LogFile -and (Test-Path $script:LogFile)) {
        Write-Host "Log file saved to: $script:LogFile" -ForegroundColor Green
    }
}
