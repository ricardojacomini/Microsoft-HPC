## 📜 Disclaim

This script is provided as-is for HPC-Pack administration. Review and test thoroughly before production use.

## HPC-pack-Insight quick usage

List available modules and run modes, or get help for parameters and usage.

Examples:

```powershell
# Show additional internal details
.\HPC-pack-Insight.ps1 -ShowHelp

# Show help/usage
.\HPC-pack-Insight.ps1 -DeepHelp

# Print only CLI tips for the selected RunMode(s)
.\HPC-pack-Insight.ps1 <RunMode> -CliTips

# List available modules/run modes
.\HPC-pack-Insight.ps1 ListModules

```

Run modes implemented:
- PortTest
- NetworkFix
- CommandTest
- NodeValidation
- NodeConfig
- ClusterMetadata
- NodeTemplates
- JobHistory
- JobDetails
- ClusterMetrics
- MetricValueHistory
- ClusterTopology
- ServicesStatus
- DiagnosticTests
- SystemInfo
- AdvancedHealth
- NodeHistory
- CommunicationTest
- SQLTrace

# Execute, gather, and export all modules ( run as adminstrator )
 powershell -NoProfile -ExecutionPolicy Unrestricted -File .\HPC-pack-Insight.ps1 All -SchedulerNode <headnode_name> -ExportToFile -ReportFile report-hpc-pack.log

---

## SQL Trace Diagnostics (HPC Pack)

Use these helper tools to capture and analyze lightweight SQL Extended Events traces for HPC Pack databases.

Prerequisites:
- Windows PowerShell 5.1
- SqlServer PowerShell module (installed on first run if missing)

Quick start:
- Discover SQL instance and next steps via Insight run mode:
	- .\HPC-pack-Insight.ps1 SQLTrace
 - Collect a short trace (saves a timestamped file and also overwrites a fixed name HPC_QuickTrace.xel):
	- .\sql-trace-collector.ps1 [-CollectSeconds 180]
 - Analyze the trace with performance overview (events/sec, p50/p95/p99, top apps):
	- .\sql-trace-analyzer.ps1
	- or specify explicitly: .\sql-trace-analyzer.ps1 -ServerInstance <server> -XeFile .\HPC_QuickTrace.xel

Notes:
- The collector targets HPCScheduler, HPCReporting, and HPCManagement databases and captures rpc_completed and sql_batch_completed events with useful actions (client app, host, login, db, sql_text).
- The collector accepts -CollectSeconds (default 120) to control capture duration. It writes both a timestamped file (e.g., HPC_QuickTrace_yyyyMMdd_HHmmss.xel) and updates a fixed convenience file (HPC_QuickTrace.xel).
- The analyzer auto-detects the SQL instance from HKLM:\SOFTWARE\Microsoft\HPC\Security\HAStorageDbConnectionString and can run without parameters. You can still pass -ServerInstance and -XeFile to pin inputs.
- If HPC_QuickTrace.xel is locked (e.g., open in SSMS/Explorer), close the viewer before deleting. The timestamped file remains as an immutable artifact.
- Help is available via -h, -help, or -ShowHelp on both collector and analyzer.

---

# Enhanced HPC Node Certificate Update Script

## Overview

The **Update-HpcNodeCertificate-Enhanced.ps1** script is an improved version of the original HPC Pack certificate update utility, designed with enhanced security, reliability, and modern PowerShell practices. This script safely updates SSL/TLS certificates used for secure communication between HPC Pack cluster nodes.

## 🔧 Key Improvements Over Original Script

### Security Enhancements
- **Secure Password Handling**: Uses `SecureString` instead of plain text passwords
- **Eliminated Hardcoded Passwords**: Removed security vulnerability from CertUtil calls
- **Native Certificate Methods**: Uses .NET certificate APIs instead of external tools
- **Input Validation**: Comprehensive parameter validation with regex patterns
- **No Password Exposure**: Prevents passwords from appearing in command lines or process lists

### Reliability Improvements
- **Certificate Quality Assessment**: Validates expiration, key usage, and compatibility
- **Retry Logic**: Service restart operations with configurable retry mechanisms
- **Enhanced Error Handling**: Detailed error messages with troubleshooting guidance
- **Dependency-Aware Operations**: Proper service restart ordering and verification
- **Rollback Capabilities**: Graceful failure handling with recovery options

### Modern PowerShell Practices
- **Advanced Functions**: Uses `[CmdletBinding()]` with proper parameter sets
- **Approved Verbs**: Consistent PowerShell verb usage throughout
- **Requirements Validation**: `#Requires` statements for prerequisites
- **Structured Logging**: Multi-level logging with UTF-8 encoding

## 📋 Prerequisites

- **PowerShell 5.1 or later**
- **Administrator privileges** (enforced by `#Requires -RunAsAdministrator`)
- **HPC Pack 2016 or later** installed on target machine
- **Valid HPC cluster node** configuration

## 🚀 Usage

### Basic Certificate Update
```powershell
# Update using existing certificate by thumbprint
.\Update-HpcNodeCertificate-Enhanced.ps1 -Thumbprint "466C3A692200566BF33ED338684299E43D3C51CE"
```

### Install New Certificate from PFX
```powershell
# Install certificate from PFX file (will prompt for password securely)
.\Update-HpcNodeCertificate-Enhanced.ps1 -PfxFilePath "C:\Certificates\new-cert.pfx"

# Install certificate with password provided as SecureString
$securePass = Read-Host -AsSecureString "Enter PFX password"
.\Update-HpcNodeCertificate-Enhanced.ps1 -PfxFilePath "C:\Certificates\new-cert.pfx" -Password $securePass
```

### Advanced Options
```powershell
# Force update even if same thumbprint is already configured
.\Update-HpcNodeCertificate-Enhanced.ps1 -Thumbprint "ABC123..." -Force

# Skip certificate expiration validation
.\Update-HpcNodeCertificate-Enhanced.ps1 -Thumbprint "ABC123..." -SkipExpirationCheck

# Apply changes after a delay
.\Update-HpcNodeCertificate-Enhanced.ps1 -Thumbprint "ABC123..." -Delay 30

# Use custom log file location
.\Update-HpcNodeCertificate-Enhanced.ps1 -Thumbprint "ABC123..." -LogFile "C:\Logs\cert-update.log"
```

## 📖 Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `PfxFilePath` | String | Yes* | Path to PFX certificate file |
| `Password` | SecureString | No | Password for PFX file (prompted if not provided) |
| `Thumbprint` | String | Yes* | Thumbprint of existing certificate (40-char hex) |
| `Delay` | Int | No | Delay in seconds before applying changes (0-3600) |
| `RunAsScheduledTask` | Switch | No | Execute as Windows scheduled task |
| `LogFile` | String | No | Custom log file path |
| `SkipExpirationCheck` | Switch | No | Skip certificate expiration validation |
| `Force` | Switch | No | Force update even if same thumbprint |

*Either `PfxFilePath` or `Thumbprint` is required (mutually exclusive parameter sets)

## 🔍 Certificate Validation

The script performs comprehensive certificate validation:

### Quality Checks
- ✅ **Private Key Validation**: Ensures certificate has private key
- ✅ **Expiration Check**: Validates certificate is not expired (unless skipped)
- ✅ **Validity Period**: Checks certificate is currently valid
- ✅ **Key Usage**: Validates key encipherment capability
- ✅ **30-Day Warning**: Warns about certificates expiring within 30 days

### Compatibility Checks
- ✅ **KeySpec Validation**: Ensures AT_KEYEXCHANGE (not AT_SIGNATURE)
- ✅ **CNG Support**: Validates CNG certificate compatibility with HPC Pack version
- ✅ **HPC Pack Version**: Checks compatibility with installed HPC Pack version
- ✅ **Service Fabric**: Special handling for Service Fabric head nodes

## 🔄 Service Management

The script intelligently manages HPC services:

### Services Managed
```
HpcManagement, HpcBroker, HpcDeployment, HpcDiagnostics,
HpcFrontendService, HpcMonitoringClient, HpcMonitoringServer,
HpcNamingService, HpcNodeManager, HpcReporting, HpcScheduler,
HpcSession, HpcSoaDiagMon, HpcWebService
```

### Restart Logic
- **Dependency Awareness**: Restarts services in proper order
- **Status Verification**: Confirms services started successfully
- **Retry Mechanism**: Up to 3 retry attempts with 5-second delays
- **Failure Handling**: Continues with other services if one fails

## 📊 Logging

### Log Levels
- **Information**: General operation progress
- **Verbose**: Detailed step-by-step actions
- **Warning**: Non-critical issues that don't stop execution
- **Error**: Critical failures that halt execution

### Log Format
```
[LogLevel] 2025-08-12 14:30:15 - Message content
```

### Default Log Location
```
%TEMP%\Update-HpcNodeCertificate-Enhanced-yyyy-MM-dd_HH-mm-ss.log
```

## ⚠️ Important Considerations

### Security
- Always run with administrator privileges
- Use secure password handling (never plain text)
- Validate certificate sources and integrity
- Monitor log files for sensitive information

### Cluster Impact
- **Brief Service Disruption**: HPC services restart during update
- **Node Communication**: Temporary communication interruption possible
- **Cluster Coordination**: Update head nodes during maintenance windows
- **Backup Certificates**: Keep backup of working certificates

### Compatibility
- **HPC Pack 2016+**: Requires HPC Pack 2016 or later
- **Windows Versions**: Tested on Windows Server 2016/2019/2022
- **PowerShell Versions**: Requires PowerShell 5.1 minimum
- **Certificate Types**: Supports RSA and ECDSA certificates

## 🛠️ Troubleshooting

### Common Issues

#### Certificate Import Failures
```powershell
# Check certificate file accessibility
Test-Path "C:\path\to\certificate.pfx"

# Verify certificate password
$cert = Get-PfxCertificate -FilePath "C:\path\to\certificate.pfx"
```

#### Service Restart Failures
```powershell
# Check service status manually
Get-Service -Name "HpcNodeManager"

# Restart individual service
Restart-Service -Name "HpcNodeManager" -Force
```

#### Registry Update Issues
```powershell
# Verify HPC registry key exists
Test-Path "HKLM:\SOFTWARE\Microsoft\HPC"

# Check current SSL thumbprint
Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\HPC" -Name SSLThumbprint
```

### Log Analysis
```powershell
# View recent log entries
Get-Content $logFile -Tail 20

# Search for errors
Select-String -Path $logFile -Pattern "\[Error\]"

# Filter by log level
Select-String -Path $logFile -Pattern "\[Warning\]|\[Error\]"
```

## 🔄 Migration from Original Script

### Parameter Changes
| Original | Enhanced | Notes |
|----------|----------|-------|
| `-Password` (String) | `-Password` (SecureString) | More secure password handling |
| N/A | `-SkipExpirationCheck` | New validation control |
| N/A | `-Force` | New force update option |

### Behavioral Changes
- **Password Prompts**: Now uses secure prompts
- **Validation**: More comprehensive certificate validation
- **Logging**: Enhanced structured logging
- **Error Handling**: Better error messages and recovery

### Migration Steps
1. **Test in Development**: Validate with test certificates first
2. **Update Automation**: Modify any automated scripts for new parameters
3. **Security Review**: Update password handling in calling scripts
4. **Documentation**: Update operational procedures

## 🤝 Contributing

### Reporting Issues
- Include full error messages from log files
- Specify HPC Pack version and Windows version
- Provide certificate details (without private information)

### Enhancement Requests
- Describe use case and expected behavior
- Consider security implications
- Test with multiple HPC Pack configurations

## 📞 Support

For HPC Pack-related issues:
- Check Microsoft HPC Pack documentation
- Review Windows Event Logs
- Consult HPC Pack community forums

For script-specific issues:
- Review generated log files
- Check PowerShell execution policies
- Validate certificate and HPC Pack prerequisites

---

## Quick Reference

### Validation Commands
```powershell
# Check HPC node status
Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\HPC"

# List certificates in Personal store
Get-ChildItem "Cert:\LocalMachine\My"

# Check certificate details
Get-ChildItem "Cert:\LocalMachine\My\THUMBPRINT" | Format-List *

# Verify HPC services
Get-Service -Name "Hpc*"
```

### Emergency Recovery
```powershell
# Restore previous certificate (if known)
.\Update-HpcNodeCertificate-Enhanced.ps1 -Thumbprint "PREVIOUS_THUMBPRINT"

# Manual service restart
Get-Service -Name "Hpc*" | Restart-Service -Force

# Check cluster connectivity
# (Use HPC Pack management tools)
```
