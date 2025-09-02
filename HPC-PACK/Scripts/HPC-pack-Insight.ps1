#requires -Version 5.1
#requires -RunAsAdministrator

<#
.SYNOPSIS
    Self-contained Microsoft HPC Pack diagnostics and troubleshooting tool with modular run modes.

    - Use -CliTips to print only CLI guidance without executing modules; use -Verbose for tips plus detailed sections.
    - CommunicationTest validates the HPCPackCommunication certificate (LocalMachine\My), with fallback discovery in Trusted Root (LocalMachine\Root) for visibility.
    - Designed for PS 5.1; run as Administrator. Requires Microsoft.Hpc module for cluster queries.

.DESCRIPTION
    A single PowerShell script that runs a comprehensive set of cluster/node checks
    and quick fixes for Microsoft HPC Pack environments. All functionality is implemented
    internally; no external script dependencies.

.PARAMETER SchedulerNode
    HPC head node name or IP. Defaults to 'headnode'.

.PARAMETER RunMode
    One of the following run modes (case-insensitive):
    - All                       : Run all checks in sequence.
    - NetworkFix                : Quick network checks and optional repairs.
    - PortTest                  : Test TCP port reachability (single or range).
    - CommandTest               : Basic Microsoft.Hpc cmdlets smoke test.
    - NodeValidation            : Summarize node states and health.
    - NodeConfig                : Local node HPC/MSMPI configuration snapshot.
    - ClusterMetadata           : Cluster overview and key properties.
    - NodeTemplates             : List node templates and groups.
    - JobHistory                : Recent jobs (supports -JobId and -NodeName/-DaysBack).
    - ClusterMetrics            : List metrics and current values.
    - MetricValueHistory        : Export historical metric values; honors -MetricStartDate, -MetricEndDate, -MetricOutputPath.
    - ClusterTopology           : Role counts and basic reachability view.
    - ServicesStatus            : HPC/MPI/SQL service states summary.
    - DiagnosticTests           : Built-in HPC Pack diagnostic tests.
    - SystemInfo                : OS and hardware basics.
    - AdvancedHealth            : Additional health probes.
    - NodeHistory               : Node state history (use with -NodeName and -DaysBack).
    - CommunicationTest         : Certificate and endpoint checks for HPC Pack communication.
    - SQLTrace                  : Quick SQL trace readiness (extract SQL instance) and guidance.
    - ListModules               : Print available run modes.

.PARAMETER FixNetworkIssues
    When set, performs optional network repair steps in NetworkFix mode (winsock reset,
    DNS flush, and basic firewall openings).

.PARAMETER EnableMpiTesting
    Reserved for future MPI verification steps.

.PARAMETER TimeoutSeconds
    General timeout (in seconds) for selected operations. Reserved for future use.

.PARAMETER ShowHelp
    Show help and available run modes.

.PARAMETER ExportToFile
    When set, exports all console output to a transcript file (default: report.log).

.PARAMETER ReportFile
    Optional path for the transcript output. Defaults to 'report.log' when -ExportToFile is used.

.PARAMETER JobId
    When provided, retrieves detailed information for the specific job using Get-HpcJobDetails.
    Can be used alone (prints only job details) or alongside other RunModes (prints job details after the selected mode).

.PARAMETER NodeName
    When used with RunMode JobHistory, also prints node state history for the specified node.

.PARAMETER DaysBack
    Number of days back to include for node history (used with -NodeName). Default is 7.

.PARAMETER CliTips
    Print only the CLI tips (PowerShell) for the selected RunMode(s). Suppresses all other
    output. Use together with -RunMode to focus on a specific section, or with -RunMode All
    to list tips from all sections.

.EXAMPLE
    .\HPC-pack-Insight.ps1 -RunMode All -SchedulerNode headnode

.EXAMPLE
    .\HPC-pack-Insight.ps1 -RunMode ClusterTopology -SchedulerNode headnode

.LINK
    Microsoft HPC Pack PowerShell command reference
    https://learn.microsoft.com/en-us/powershell/high-performance-computing/microsoft-hpc-pack-command-reference?view=hpc19-ps
    https://learn.microsoft.com/en-us/powershell/high-performance-computing/using-service-log-files-for-hpc-pack?view=hpc19-ps

.NOTES
    Author         : Ricardo S Jacomini
    Team           : Azure HPC + AI  
    Email          : ricardo.jacomini@microsoft.com
    Version        : 0.7.0
    Last Modified  : 2025-08-15
    Script Name    : HPC-pack-Insight.ps1
    Tags           : Diagnostics, HPCPack
#>


[CmdletBinding()]
param(
    [string]$RunMode = "All",
    [string]$SchedulerNode = "headnode",
    # Optional client certificate inputs for CommunicationTest when running off a compute node
    [string]$ClientCertThumbprint,
    [string]$ClientCertPfxPath,
    [securestring]$ClientCertPfxPassword,
    [switch]$FixNetworkIssues,
    [switch]$TestHpcNodePorts,
    [int[]]$Ports,
    [int]$Port,
    [switch]$EnableMpiTesting,
    [int]$TimeoutSeconds = 120,
    [Alias('h','help')]
    [switch]$ShowHelp,
    [switch]$DeepHelp,
    [switch]$ExportToFile,
    [Alias('Out','Log','LogFile')]
    [string]$ReportFile = 'report.log',
    [int]$JobId,
    [string]$NodeName,
    [int]$DaysBack = 7,
    [switch]$CliTips,
    [datetime]$MetricStartDate,
    [datetime]$MetricEndDate,
    [string]$MetricOutputPath
)

$ErrorActionPreference = 'Stop'

# Script filename for dynamic help/usage strings
try {
    if ($PSCommandPath) { $Script:SelfName = Split-Path -Path $PSCommandPath -Leaf }
    elseif ($MyInvocation -and $MyInvocation.MyCommand -and $MyInvocation.MyCommand.Name) { $Script:SelfName = $MyInvocation.MyCommand.Name }
    else { $Script:SelfName = 'script.ps1' }
} catch { $Script:SelfName = 'script.ps1' }

# CLI tips-only logic for single run mode

# Normalize alternate help triggers passed as raw args (e.g., --help or -?)
if ($args -contains '--help' -or $args -contains '-?') { $ShowHelp = $true }
if ($args -contains '--deephelp') { $DeepHelp = $true }
# Support GNU-style verbose flag for convenience
if ($args -contains '--verbose') { $VerbosePreference = 'Continue' }
# If DeepHelp is requested alone, treat it as ShowHelp too
if ($DeepHelp -and -not $ShowHelp) { $ShowHelp = $true }

# Flag to control tips-only output mode
$Script:CliTipsOnly = [bool]$CliTips
if ($Script:CliTipsOnly) { $VerbosePreference = 'SilentlyContinue' }

### Tips-only block: run after all functions are defined
# At the end of the script, add:


# Note: HPC CLI token '/detailed:true' is not a valid RunMode; prefer -Verbose or pass it to 'job view' directly.

function Write-Header {
    param([string]$Title)
    $sep = '=' * 90
    Write-Host $sep -ForegroundColor Cyan
    Write-Host ("  " + $Title) -ForegroundColor Yellow
    Write-Host ("  Generated: " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) -ForegroundColor Gray
    Write-Host $sep -ForegroundColor Cyan
}

function Import-HpcModule {
    param([switch]$Quiet)
    $imported = $false
    $oldVerbose = $VerbosePreference
    $VerbosePreference = 'SilentlyContinue'
    $candidates = @(
        'C:\Program Files\Microsoft HPC Pack 2019\PowerShell\Microsoft.Hpc.dll',
        'C:\Program Files\Microsoft HPC Pack 2016\PowerShell\Microsoft.Hpc.dll'
    )
    foreach ($path in $candidates) {
        if (Test-Path -LiteralPath $path) {
            try {
                Import-Module -Name $path -DisableNameChecking -ErrorAction Stop -Verbose:$false
                if (-not $Quiet) { Write-Host "HPC module imported from: $path" -ForegroundColor Green }
                $imported = $true; break
            } catch {
                if (-not $Quiet) { Write-Warning "Failed importing HPC module from: $path - $($_.Exception.Message)" }
            }
        }
    }
    if (-not $imported) {
        try {
            Import-Module -Name Microsoft.Hpc -DisableNameChecking -ErrorAction Stop -Verbose:$false
            if (-not $Quiet) { Write-Host "HPC module imported by name: Microsoft.Hpc" -ForegroundColor Green }
            $imported = $true
        } catch {
            if (-not $Quiet) { Write-Warning "HPC PowerShell module not found in default locations. Some run modes may be limited." }
        }
    }
    $VerbosePreference = $oldVerbose
    return $imported
}

function Write-Section {
    param([string]$Title,[string]$Color='Green')
    if ($Script:CliTipsOnly) { return }
    Write-Host ""; Write-Host ("-"*90) -ForegroundColor $Color
    Write-Host ("  " + $Title) -ForegroundColor $Color
    Write-Host ("-"*90) -ForegroundColor $Color
}

# Helper: header for CLI tips-only mode
function Write-CliHeader {
    param([string]$Name)
    if (-not $Name) { return }
    Write-Host ""
    Write-Host ("===== {0} ======" -f $Name) -ForegroundColor Yellow
    Write-Host ""
}

# Helper: emit a compact CLI tips block only when -Verbose is enabled
function Write-CliTips {
    param([string[]]$Lines)
    if (-not $Lines -or $Lines.Count -eq 0) { return }
    
    # Helper to print in pairs (description then command) and add a blank line between entries
    function _PrintTips([string[]]$arr,[switch]$Indented){
        $i = 0
        while ($i -lt $arr.Count) {
            $line = $arr[$i]
            if ($null -ne $line -and $line -ne '') {
                $prefix = if ($Indented) { '  ' } else { '' }
                $isDesc = $line.TrimStart().StartsWith('#')
                $lineColor = if ($isDesc) { 'Cyan' } else { 'DarkGray' }
                Microsoft.PowerShell.Utility\Write-Host ("$prefix$line") -ForegroundColor $lineColor
                # If this looks like a description (starts with '#') and another line exists, print the next line as command on same entry
                if ($line.TrimStart().StartsWith('#') -and ($i + 1) -lt $arr.Count) {
                    $cmd = $arr[$i+1]
                    if ($null -ne $cmd -and $cmd -ne '') {
                        Microsoft.PowerShell.Utility\Write-Host ("$prefix$cmd") -ForegroundColor DarkGray
                        $i++
                    }
                }
                # Blank line between entries
                Microsoft.PowerShell.Utility\Write-Host ""
            }
            $i++
        }
    }

    if ($Script:CliTipsOnly) {
        _PrintTips -arr $Lines
        return
    }
    if ($VerbosePreference -ne 'Continue') { return }
    Microsoft.PowerShell.Utility\Write-Host ""
    Microsoft.PowerShell.Utility\Write-Host "CLI tips (PowerShell):" -ForegroundColor Gray
    _PrintTips -arr $Lines -Indented
}

# Performs network repair actions (winsock reset, DNS flush, and firewall port openings)
function Repair-NetworkConnectivity {
    param([int[]]$Ports = @(80,443,9087,9090,9091,9094))
    try { netsh winsock reset | Out-Null; Write-Host "  ✅ Winsock reset" -ForegroundColor Green } catch { Write-Host "  ❌ Winsock reset failed: $($_.Exception.Message)" -ForegroundColor Red }
    try { ipconfig /flushdns | Out-Null; Write-Host "  ✅ Flushed DNS" -ForegroundColor Green } catch { Write-Host "  ❌ Flush DNS failed: $($_.Exception.Message)" -ForegroundColor Red }
    foreach($p in $Ports){
        try{
            $rn = "HPC-Port-$p"
            if(-not (Get-NetFirewallRule -DisplayName $rn -ErrorAction SilentlyContinue)){
                New-NetFirewallRule -DisplayName $rn -Direction Inbound -Protocol TCP -LocalPort $p -Action Allow -Profile Any | Out-Null
                Write-Host "  ✅ Firewall rule for $p" -ForegroundColor Green
            } else { Write-Host "  ℹ️  Firewall rule exists for $p" -ForegroundColor Cyan }
        } catch { Write-Host "  ❌ Firewall rule $p failed: $($_.Exception.Message)" -ForegroundColor Red }
    }
}

# Helper: test TCP port reachability against a node (supports ranges like @(40000..40003))
function Test-HpcNodePorts {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][string]$NodeName,
        [int[]]$Ports,
        [switch]$Quiet
    )
    try {
        if (-not $Ports -or $Ports.Count -eq 0) {
            # Default to common HPC Pack ports if none provided
            $Ports = @(80,443,9087,9090,9091,9094)
        }
        foreach ($port in $Ports) {
            try {
                $isOpen = Test-NetConnection -ComputerName $NodeName -Port $port -InformationLevel Quiet
                if ($isOpen) {
                    Write-Host ("✅ Port {0} is open on {1}" -f $port, $NodeName) -ForegroundColor Green
                } elseif (-not $Quiet) {
                    Write-Warning ("❌ Port {0} is closed or unreachable on {1}" -f $port, $NodeName)
                }
            } catch {
                if (-not $Quiet) { Write-Warning ("⚠️  Error testing port {0} on {1}: {2}" -f $port, $NodeName, $_.Exception.Message) }
            }
        }
    } catch {
        if (-not $Quiet) { Write-Warning ("⚠️  Test-HpcNodePorts failed: {0}" -f $_.Exception.Message) }
    }
}

# Self-contained implementations for each RunMode
function Invoke-NetworkFix {
    if ($Script:CliTipsOnly) {
    Write-CliHeader -Name 'Network Fix'
        Write-CliTips @(
            '# Repair network connectivity',
            'netsh winsock reset',
            '# Open common HPC ports in firewall',
            'New-NetFirewallRule -DisplayName "HPC-Port-40000" -Direction Inbound -Protocol TCP -LocalPort 40000 -Action Allow -Profile Any',
            "# Show IPv4 default route",
            "Get-NetRoute -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0'",
            "# Show IPv6 default route",
            "Get-NetRoute -AddressFamily IPv6 -DestinationPrefix '::/0'",
            "# DNS resolution test",
            "Resolve-DnsName microsoft.com; Resolve-DnsName azure.com",
            "# Repairs (optional): netsh winsock reset; ipconfig /flushdns",
            "# Check MS-MPI version in registry",
            "Get-ItemProperty 'HKLM:\\SOFTWARE\\Microsoft\\MPI' | Select Version",
            "# Check MS-MPI Launch and MPI services",
            "Get-Service MSMpiLaunchSvc, msmpi -ErrorAction SilentlyContinue | Select Name,Status,StartType",
            "# Local MPI smoke test",
            "mpiexec -n 1 hostname",
            "# Test a range of TCP ports via NetworkFix run mode",
            "Test-HpcNodePorts -NodeName $SchedulerNode -Port 443",
            "Test-HpcNodePorts -NodeName IaaSCN104 -Ports @(40000..40003)",
            "# List HPC nodes and states",
            "Get-HpcNode -Scheduler $SchedulerNode | Select NetBiosName,NodeState,HealthState,NodeTemplate | Format-Table -Auto",
            "# Reachability: ",
            "Test-Connection <NodeName> -Count 1 -Quiet"    
            )
        return
    }
    Write-Section "NETWORK CONNECTIVITY CHECKS"
    try {
        $gw4 = (Get-NetRoute -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Sort-Object RouteMetric | Select-Object -First 1).NextHop
        $gw6 = (Get-NetRoute -AddressFamily IPv6 -DestinationPrefix '::/0' -ErrorAction SilentlyContinue | Sort-Object RouteMetric | Select-Object -First 1).NextHop
        $gw = if ($gw4) { $gw4 } elseif ($gw6) { $gw6 } else { $null }
        if ($gw) {
            $ok = Test-Connection -ComputerName $gw -Count 1 -Quiet -ErrorAction SilentlyContinue
            if ($ok) { Write-Host "  ✅ Default gateway reachable ($gw)" -ForegroundColor Green }
            else { Write-Host "  ❌ Default gateway not responding to ping ($gw)" -ForegroundColor Red }
        } else {
            Write-Host "  ⚠️  No default route found (IPv4 or IPv6)" -ForegroundColor Yellow
        }
        # DNS reachability quick check for common hosts
        $dnsHosts = @('microsoft.com','azure.com')
        foreach ($h in $dnsHosts) {
            try {
                if (Resolve-DnsName $h -ErrorAction Stop -Verbose:$false) { Write-Host "   ✅ $h" -ForegroundColor Green }
            } catch { Write-Host "   ❌ $h" -ForegroundColor Red }
        }
    }
    catch { }

    # Verbose network snapshot when -Verbose was provided to the script
    if ($VerbosePreference -eq 'Continue') {
        Write-Host ""; Write-Host "VERBOSE NETWORK SNAPSHOT" -ForegroundColor White
        Write-Host ("-"*60) -ForegroundColor White
        try {
            $gwRaw = @(Get-NetIPConfiguration -ErrorAction SilentlyContinue | Select-Object -ExpandProperty IPv4DefaultGateway) | Where-Object { $_ }
            if ($gwRaw -and $gwRaw.Count -gt 0) {
                $gwRows = foreach ($g in $gwRaw) {
                    if (-not $g) { continue }
                    $ifm = $null; $ps = $null
                    try { $ifm = (Get-NetIPInterface -InterfaceIndex $g.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).InterfaceMetric } catch {}
                    try {
                        $route = Get-NetRoute -AddressFamily IPv4 -InterfaceIndex $g.ifIndex -DestinationPrefix $g.DestinationPrefix -ErrorAction SilentlyContinue |
                                 Where-Object { $_.NextHop -eq $g.NextHop } |
                                 Sort-Object RouteMetric |
                                 Select-Object -First 1
                        if ($route) { $ps = $route.PolicyStore }
                    } catch {}
                    [pscustomobject]@{
                        ifIndex           = $g.ifIndex
                        DestinationPrefix = $g.DestinationPrefix
                        NextHop           = $g.NextHop
                        RouteMetric       = $g.RouteMetric
                        ifMetric          = $ifm
                        PolicyStore       = $ps
                    }
                }
                $gwText = $gwRows | Format-Table ifIndex,DestinationPrefix,NextHop,RouteMetric,ifMetric,PolicyStore -AutoSize | Out-String -Width 200
                if ($gwText) { $gwText.TrimEnd() | Write-Host -ForegroundColor White }
            }
        } catch {}

        try {
            $upAdapters = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' }
            if ($upAdapters) {
                foreach ($ad in $upAdapters) {
                    # Validate the interface index still exists to avoid NetTCPIP module throwing (race conditions, virtual adapters)
                    $ifPresent = Get-NetIPInterface -InterfaceIndex $ad.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
                    if (-not $ifPresent) {
                        if ($VerbosePreference -eq 'Continue') { Write-Host ("  Skipping adapter idx {0} (no MSFT_NetIPInterface)" -f $ad.ifIndex) -ForegroundColor DarkGray }
                        continue
                    }
                    # Suppress transient module errors; fall back to a broad query if needed
                    $cfg = $null
                    try {
                        $cfg = Get-NetIPConfiguration -InterfaceIndex $ad.ifIndex -ErrorAction Stop 2>$null
                    } catch {
                        $cfg = Get-NetIPConfiguration -ErrorAction SilentlyContinue 2>$null | Where-Object { ($_.InterfaceIndex -eq $ad.ifIndex) -or ($_.InterfaceAlias -eq $ad.InterfaceAlias) } | Select-Object -First 1
                    }
                    if ($cfg) {
                        $ipv4s = @()
                        if ($cfg.IPv4Address) {
                            $ipv4s = $cfg.IPv4Address |
                                ForEach-Object {
                                    if ($_.IPv4Address) { $_.IPv4Address }
                                    elseif ($_.IPAddress) { $_.IPAddress }
                                }
                        }
                        try {
                            $dns4 = (Get-DnsClientServerAddress -InterfaceIndex $ad.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses
                        } catch {}
                        Write-Host "Adapter:" -ForegroundColor Yellow
                        Write-Host ("  InterfaceAlias.......: {0}" -f $ad.InterfaceAlias) -ForegroundColor White
                        Write-Host ("  InterfaceIndex.......: {0}" -f $ad.ifIndex) -ForegroundColor White
                        Write-Host ("  InterfaceDescription.: {0}" -f $ad.InterfaceDescription) -ForegroundColor White
                        if ($cfg.NetProfile -and $cfg.NetProfile.Name) { Write-Host ("  NetProfile.Name......: {0}" -f $cfg.NetProfile.Name) -ForegroundColor White }
                        if ($ipv4s.Count -gt 0) { Write-Host ("  IPv4Address..........: {0}" -f ($ipv4s -join ', ')) -ForegroundColor White }
                        if ($gw4) { Write-Host ("  IPv4DefaultGateway...: {0}" -f $gw4) -ForegroundColor White }
                        if ($dns4 -and $dns4.Count -gt 0) { Write-Host ("  DNSServer............: {0}" -f ($dns4 -join ', ')) -ForegroundColor White }
                        Write-Host "" -ForegroundColor White
                    }
                }
            }
        } catch {}
    }

    $doRepair = $FixNetworkIssues -or ($RunMode -eq 'NetworkFix')
    if ($doRepair) {
        Write-Section "NETWORK REPAIR ACTIONS" 'Yellow'
        Repair-NetworkConnectivity
    }
    if ($TestHpcNodePorts) {
        Write-Section "PORT REACHABILITY TEST" 'Yellow'
        $targetNode = if ($NodeName) { $NodeName } else { $SchedulerNode }
        $portList = if ($Port) { @($Port) }
                   elseif ($Ports) { $Ports }
                   else { @(80,443,9087,9090,9091,9094) }
        Write-Host ("  Target Node: {0}" -f $targetNode) -ForegroundColor White
        Write-Host ("  Ports......: {0}" -f ($portList -join ', ')) -ForegroundColor White
        Test-HpcNodePorts -NodeName $targetNode -Ports $portList
    }
}

function Invoke-CommandTest {
    if ($Script:CliTipsOnly) {
    Write-CliHeader -Name 'Command Test'
        Write-CliTips @(
            "# Import HPC PowerShell module",
            "Import-Module Microsoft.Hpc",
            "# Quick cluster overview (name/version/node count)",
            "Get-HpcClusterOverview -Scheduler $SchedulerNode"
            )
        return
    }

    Write-Section "HPC COMMAND TESTING"
    if (-not (Import-HpcModule -Quiet)) { Write-Host "  ❌ HPC module not available" -ForegroundColor Red; return }
    try {
        $ov = Get-HpcClusterOverview -Scheduler $SchedulerNode -ErrorAction Stop
        if($ov){
            Write-Host "  ✅ Cluster: $($ov.ClusterName) | Version: $($ov.Version) | Nodes: $($ov.TotalNodeCount)" -ForegroundColor Green
        }
    } catch { Write-Host "  ❌ Get-HpcClusterOverview: $($_.Exception.Message)" -ForegroundColor Red }
}

function Invoke-NodeValidation {
    if ($Script:CliTipsOnly) {
    Write-CliHeader -Name 'NodeValidation'
        Write-CliTips @(
            '# Summarize node states and health',
            'Get-HpcNode -Scheduler <SchedulerNode> | Select NetBiosName,NodeState,HealthState | Format-Table -Auto'
            "# Count nodes by state",
            "Get-HpcNode -Scheduler $SchedulerNode | Group-Object NodeState | Select Name,Count",
            "# Count nodes by health",
            "Get-HpcNode -Scheduler $SchedulerNode | Group-Object HealthState | Select Name,Count",
            "# First 10 nodes with HealthState != OK",
            "Get-HpcNode -Scheduler $SchedulerNode | Where-Object { $_.HealthState -ne 'OK' } | Select NetBiosName,NodeState,HealthState -First 10"
            "# OS version and architecture",
            "Get-CimInstance Win32_OperatingSystem | Select Caption,Version,OSArchitecture",
            "# Computer name, domain, and memory",
            "Get-CimInstance Win32_ComputerSystem | Select Name,Domain,TotalPhysicalMemory"
        )
        return
    }
    Write-Section "COMPREHENSIVE HPC NODE VALIDATION"
    if (-not (Import-HpcModule -Quiet)) { Write-Host "  ❌ HPC module not available. Skipping." -ForegroundColor Red; return }
    try { $nodes = Get-HpcNode -Scheduler $SchedulerNode -ErrorAction SilentlyContinue } catch { $nodes = $null }
    if ($nodes) {
        $online  = ($nodes | Where-Object { $_.NodeState -eq 'Online' }).Count
        $healthy = ($nodes | Where-Object { $_.HealthState -eq 'OK' }).Count
        Write-Host "  🖥️  Nodes: $($nodes.Count) | Online: $online | Healthy: $healthy" -ForegroundColor White
        $crit = $nodes | Where-Object { $_.NodeState -ne 'Online' -or $_.HealthState -ne 'OK' } | Select-Object -First 10
        if ($crit) {
            Write-Host "  ⚠️  Nodes needing attention:" -ForegroundColor Yellow
            $crit | ForEach-Object { Write-Host "    $($_.NetBiosName): State=$($_.NodeState) Health=$($_.HealthState)" }
        }

        # Verbose: deeper breakdowns and optional per-node snapshot
        if ($VerbosePreference -eq 'Continue') {
            Write-Host ""; Write-Host "Breakdown by State:" -ForegroundColor Green
            try {
                $stateGroups = $nodes | Group-Object NodeState | Sort-Object Count -Descending
                foreach ($g in $stateGroups) { Write-Host ("   {0,-12}: {1}" -f $g.Name, $g.Count) -ForegroundColor White }
            } catch {}

            Write-Host ""; Write-Host "Breakdown by Health:" -ForegroundColor Green
            try {
                $healthGroups = $nodes | Group-Object HealthState | Sort-Object Count -Descending
                foreach ($g in $healthGroups) { Write-Host ("   {0,-12}: {1}" -f $g.Name, $g.Count) -ForegroundColor White }
            } catch {}

            # Role counts (best-effort across NodeRole/NodeType)
            try {
                function _GetRoleCount([object[]]$ns,[string]$roleName){
                    $pattern = switch ($roleName) {
                        'HeadNode'    { '(?i)Head|\bHN\b' }
                        'ComputeNode' { '(?i)Compute|\bCN\b' }
                        'BrokerNode'  { '(?i)Broker|\bBN\b' }
                        default       { [regex]::Escape($roleName) }
                    }
                    ($ns | Where-Object {
                        $isMatch = $false
                        if ($_.PSObject.Properties['NodeRole'] -and $_.NodeRole) {
                            $roleStr = ("{0}" -f ($_.NodeRole -join ','))
                            if ($roleStr -match $pattern) { $isMatch = $true }
                        }
                        if (-not $isMatch -and $_.PSObject.Properties['NodeType'] -and $_.NodeType) {
                            if (("{0}" -f $_.NodeType) -match $pattern) { $isMatch = $true }
                        }
                        if (-not $isMatch -and $roleName -eq 'HeadNode') {
                            # Treat scheduler node as head node as a fallback heuristic
                            if ($_.NetBiosName -and $SchedulerNode -and ("$($_.NetBiosName)" -ieq "$SchedulerNode")) { $isMatch = $true }
                        }
                        return $isMatch
                    }).Count
                }
                $headCnt    = _GetRoleCount -ns $nodes -roleName 'HeadNode'
                $computeCnt = _GetRoleCount -ns $nodes -roleName 'ComputeNode'
                $brokerCnt  = _GetRoleCount -ns $nodes -roleName 'BrokerNode'
                Write-Host ""; Write-Host "Role Counts:" -ForegroundColor Green
                Write-Host ("   Head Nodes...........: {0}" -f $headCnt) -ForegroundColor White
                Write-Host ("   Compute Nodes........: {0}" -f $computeCnt) -ForegroundColor White
                Write-Host ("   Broker Nodes.........: {0}" -f $brokerCnt) -ForegroundColor White
            } catch {}

            # Detailed per-node table (cap reachability checks for large clusters)
            Write-Host ""; Write-Host "Detailed Node Snapshot:" -ForegroundColor Green
            $fmt = "{0,-18} {1,-10} {2,-10} {3,-15} {4,-12}"
            Write-Host ($fmt -f 'NAME','STATE','HEALTH','TEMPLATE','REACHABLE') -ForegroundColor White
            Write-Host ("-"*70) -ForegroundColor White
            $doPing = $nodes.Count -le 50
            if (-not $doPing) { Write-Host "   (Reachability checks skipped for >50 nodes)" -ForegroundColor Yellow }
            foreach ($n in ($nodes | Sort-Object NetBiosName)) {
                $template = if ($n.PSObject.Properties['NodeTemplate'] -and $n.NodeTemplate) { "$($n.NodeTemplate)" } else { 'Default' }
                $reach = 'Skipped'
                if ($doPing) {
                    try { $ok = Test-Connection -ComputerName $n.NetBiosName -Count 1 -Quiet -ErrorAction SilentlyContinue; $reach = if ($ok) { 'Yes' } else { 'No' } } catch { $reach = 'Error' }
                }
                Write-Host ($fmt -f $n.NetBiosName, $n.NodeState, $n.HealthState, $template, $reach) -ForegroundColor White
            }
        }
    }
    else {
        Write-Host "  ⚠️  No node data returned" -ForegroundColor Yellow
    }

}

function Invoke-NodeConfig {
    if ($Script:CliTipsOnly) {
        Write-CliHeader -Name 'Node Config'
        Write-CliTips @(
            '# HPC registry values on this node',
            "Get-ItemProperty 'HKLM:\\SOFTWARE\\Microsoft\\HPC'",
            '# Computer identity and domain',
            'Get-CimInstance Win32_ComputerSystem | Select Name,Domain',
            '# MS-MPI service states',
            'Get-Service MsMpiLaunchSvc, msmpi -ErrorAction SilentlyContinue | Select Name,Status,StartType',
            '# Sample CPU usage once',
            "Get-Counter '\\Processor(_Total)\\% Processor Time' -SampleInterval 1 -MaxSamples 1",
            '# Available memory (MB)',
            "Get-Counter '\\Memory\\Available MBytes' -SampleInterval 1 -MaxSamples 1"
            "# HPC registry values on this node",
            "Get-ItemProperty 'HKLM:\\SOFTWARE\\Microsoft\\HPC'",
            "# Computer identity and domain",
            "Get-CimInstance Win32_ComputerSystem | Select Name,Domain",
            "# MS-MPI service states",
            "Get-Service MsMpiLaunchSvc, msmpi -ErrorAction SilentlyContinue | Select Name,Status,StartType"
            "# Sample CPU usage once",
            "Get-Counter '\\Processor(_Total)\\% Processor Time' -SampleInterval 1 -MaxSamples 1",
            "# Available memory (MB)",
            "Get-Counter '\\Memory\\Available MBytes' -SampleInterval 1 -MaxSamples 1"
        )
        return
    }
    Write-Section "NODE CONFIGURATION"
    $key = 'HKLM:\SOFTWARE\Microsoft\HPC'
    if(Test-Path $key){
        $v = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
        Write-Host "  InstalledRole: $($v.InstalledRole)" -ForegroundColor White
        Write-Host "  SSLThumbprint: $($v.SSLThumbprint)" -ForegroundColor White
        Write-Host "  ClusterConnectionString: $($v.ClusterConnectionString)" -ForegroundColor White

        if ($VerbosePreference -eq 'Continue') {
            # Extended details when -Verbose
            try {
                $compName = $env:COMPUTERNAME
                $domain   = if ($env:USERDNSDOMAIN) { $env:USERDNSDOMAIN } else { (Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue).Domain }
                $rolesRaw = $v.InstalledRole
                $roles    = if ($rolesRaw -is [array]) { $rolesRaw -join ', ' } else { [string]$rolesRaw }
                # Consider role strings like HN or Head
                $isHead   = if ($roles -match '(?i)\bHN\b|head') { $true } else { $false }
                $sfhn     = if ($v.PSObject.Properties['ServiceFabricHN']) { $v.ServiceFabricHN } else { 'n/a' }

                Write-Host ("  Computer Name........: {0}" -f $compName) -ForegroundColor White
                Write-Host ("  Domain...............: {0}" -f $domain) -ForegroundColor White
                Write-Host ("  Installed Role(s)....: {0}" -f $roles) -ForegroundColor White
                Write-Host ("  Is Head Node.........: {0}" -f $isHead) -ForegroundColor White
                Write-Host ("  Service Fabric HN....: {0}" -f $sfhn) -ForegroundColor White

                # HPC Pack Version via cluster overview if available
                $edition = 'Unknown'
                $verText = 'Unknown'
                try {
                    if (Get-Command Get-HpcClusterOverview -ErrorAction SilentlyContinue) {
                        $ov = Get-HpcClusterOverview -Scheduler $SchedulerNode -ErrorAction SilentlyContinue
                        if ($ov -and $ov.Version) {
                            $verText = [string]$ov.Version
                            $major = $ov.Version.Major
                            switch ($major) { 5 { $edition = 'HPC Pack 2016' } 6 { $edition = 'HPC Pack 2019' } default { $edition = 'Unknown HPC Pack version' } }
                        }
                    }
                } catch {}

                # Explicitly show MS-MPI Launch Service status if present
                try {
                    $launch = Get-Service -Name 'MSMpiLaunchSvc' -ErrorAction SilentlyContinue
                    if ($launch) {
                        $launchStart = try { (Get-CimInstance -ClassName Win32_Service -Filter "Name='MSMpiLaunchSvc'" -ErrorAction SilentlyContinue).StartMode } catch { $null }
                        $launchStartText = if ($launchStart) { $launchStart } else { 'Unknown' }
                        Write-Host ("  Launch Service........: {0} ({1}) StartType={2}" -f $launch.Status, $launch.DisplayName, $launchStartText) -ForegroundColor White
                    } else {
                        Write-Host "  Launch Service........: Not installed" -ForegroundColor DarkGray
                    }
                } catch {}
                Write-Host ("  HPC Pack Version.....: {0}" -f $verText) -ForegroundColor White
                Write-Host ("  Product Edition......: {0}" -f $edition) -ForegroundColor White
            } catch {}
        }

    } else { Write-Host "  ⚠️  HPC registry key not found" -ForegroundColor Yellow }
    

}

function Invoke-ClusterMetadata {
    if ($Script:CliTipsOnly) {
        Write-CliHeader -Name 'Cluster Metadata'
        Write-CliTips @(
            "# Cluster overview",
            "Get-HpcClusterOverview -Scheduler $SchedulerNode",
            "# All cluster properties",
            "Get-HpcClusterProperty -Scheduler $SchedulerNode | Select Name,Value"
        )
        return
    }
    Write-Section "CLUSTER METADATA & OVERVIEW"
    if (Import-HpcModule -Quiet) {
        try {
            $ov = Get-HpcClusterOverview -Scheduler $SchedulerNode -ErrorAction SilentlyContinue
            if ($ov) {
                # Concise default line
                Write-Host ("  Name: {0} | Version: {1} | Nodes: {2}" -f $ov.ClusterName, $ov.Version, $ov.TotalNodeCount) -ForegroundColor White

                if ($VerbosePreference -eq 'Continue') {
                    # Detailed overview metrics
                    Write-Host ""; Write-Host "Cluster Overview:" -ForegroundColor Green
                    Write-Host ("   Cluster Name.........: {0}" -f $ov.ClusterName) -ForegroundColor White
                    Write-Host ("   HPC Pack Version.....: {0}" -f $ov.Version) -ForegroundColor White
                    Write-Host ("   Total Nodes..........: {0}" -f $ov.TotalNodeCount) -ForegroundColor White
                    if ($ov.PSObject.Properties['ReadyNodeCount'])       { Write-Host ("   Ready Nodes..........: {0}" -f $ov.ReadyNodeCount) -ForegroundColor White }
                    if ($ov.PSObject.Properties['OfflineNodeCount'])     { Write-Host ("   Offline Nodes........: {0}" -f $ov.OfflineNodeCount) -ForegroundColor White }
                    if ($ov.PSObject.Properties['DrainingNodeCount'])    { Write-Host ("   Draining Nodes.......: {0}" -f $ov.DrainingNodeCount) -ForegroundColor White }
                    if ($ov.PSObject.Properties['UnreachableNodeCount']) { Write-Host ("   Unreachable Nodes....: {0}" -f $ov.UnreachableNodeCount) -ForegroundColor White }
                    if ($ov.PSObject.Properties['TotalCoreCount'])       { Write-Host ("   Total CPU Cores......: {0}" -f $ov.TotalCoreCount) -ForegroundColor White }
                    if ($ov.PSObject.Properties['BusyCoreCount'])        { Write-Host ("   Busy Cores...........: {0}" -f $ov.BusyCoreCount) -ForegroundColor White }
                    if ($ov.PSObject.Properties['IdleCoreCount'])        { Write-Host ("   Idle Cores...........: {0}" -f $ov.IdleCoreCount) -ForegroundColor White }
                    if ($ov.PSObject.Properties['OfflineCoreCount'])     { Write-Host ("   Offline Cores........: {0}" -f $ov.OfflineCoreCount) -ForegroundColor White }
                    if ($ov.PSObject.Properties['TotalJobCount'])        { Write-Host ("   Total Jobs...........: {0}" -f $ov.TotalJobCount) -ForegroundColor White }
                    if ($ov.PSObject.Properties['RunningJobCount'])      { Write-Host ("   Running Jobs.........: {0}" -f $ov.RunningJobCount) -ForegroundColor White }
                    if ($ov.PSObject.Properties['QueuedJobCount'])       { Write-Host ("   Queued Jobs..........: {0}" -f $ov.QueuedJobCount) -ForegroundColor White }
                    if ($ov.PSObject.Properties['FinishedJobCount'])     { Write-Host ("   Finished Jobs........: {0}" -f $ov.FinishedJobCount) -ForegroundColor White }
                    if ($ov.PSObject.Properties['FailedJobCount'])       { Write-Host ("   Failed Jobs..........: {0}" -f $ov.FailedJobCount) -ForegroundColor White }
                    if ($ov.PSObject.Properties['TotalTaskCount'])       { Write-Host ("   Total Tasks..........: {0}" -f $ov.TotalTaskCount) -ForegroundColor White }
                    if ($ov.PSObject.Properties['RunningTaskCount'])     { Write-Host ("   Running Tasks........: {0}" -f $ov.RunningTaskCount) -ForegroundColor White }
                    if ($ov.PSObject.Properties['QueuedTaskCount'])      { Write-Host ("   Queued Tasks.........: {0}" -f $ov.QueuedTaskCount) -ForegroundColor White }
                    if ($ov.PSObject.Properties['FinishedTaskCount'])    { Write-Host ("   Finished Tasks.......: {0}" -f $ov.FinishedTaskCount) -ForegroundColor White }
                    if ($ov.PSObject.Properties['FailedTaskCount'])      { Write-Host ("   Failed Tasks.........: {0}" -f $ov.FailedTaskCount) -ForegroundColor White }

                    # Cluster properties section
                    try {
                        $props = Get-HpcClusterProperty -Scheduler $SchedulerNode -ErrorAction SilentlyContinue
                    } catch { $props = $null }
                    if ($props) {
                        Write-Host ""; Write-Host "Cluster Properties:" -ForegroundColor Green
                        $important = @('CCP_CLUSTER_NAME','InstallCredential','NodeNamingSeries','CCP_MPI_NETMASK','HPC_RUNTIMESHARE','SchedulingMode','AutomaticGrowthEnabled','AutomaticShrinkEnabled')
                        foreach ($name in $important) {
                            $p = $props | Where-Object { $_.Name -eq $name }
                            if ($p) {
                                $display = switch ($p.Name) {
                                    'CCP_CLUSTER_NAME' { 'Cluster Name' }
                                    'InstallCredential' { 'Install Credential' }
                                    'NodeNamingSeries' { 'Node Naming Series' }
                                    'CCP_MPI_NETMASK' { 'MPI Network Mask' }
                                    'HPC_RUNTIMESHARE' { 'Runtime Share' }
                                    'SchedulingMode' { 'Scheduling Mode' }
                                    'AutomaticGrowthEnabled' { 'Auto Growth Enabled' }
                                    'AutomaticShrinkEnabled' { 'Auto Shrink Enabled' }
                                    default { $p.Name }
                                }
                                Write-Host ("   {0,-20}: {1}" -f $display, $p.Value) -ForegroundColor White
                            }
                        }

                        Write-Host ""; Write-Host "   Azure Configuration:" -ForegroundColor White
                        $az = $props | Where-Object { $_.Name -like '*Azure*' -and $_.Value } | Select-Object -First 5
                        if ($az) {
                            foreach ($p in $az) {
                                $val = if ($p.Value -and $p.Value.Length -gt 50) { $p.Value.Substring(0,47) + '...' } else { $p.Value }
                                Write-Host ("     {0}: {1}" -f $p.Name, $val) -ForegroundColor White
                            }
                        } else { Write-Host "     No Azure-specific configuration found" -ForegroundColor White }

                        Write-Host ""; Write-Host "   Job & Scheduling Settings:" -ForegroundColor White
                        $jobProps = @('TtlCompletedJobs','JobRetryCount','TaskRetryCount','PreemptionType','ReBalancingInterval')
                        foreach ($name in $jobProps) {
                            $p = $props | Where-Object { $_.Name -eq $name }
                            if ($p) { Write-Host ("     {0}: {1}" -f $p.Name, $p.Value) -ForegroundColor White }
                        }
                    }
                }
            }
        } catch {}

    } else {
        Write-Host "  ⚠️  HPC module not available" -ForegroundColor Yellow
    }
}

function Invoke-NodeTemplates {
    if ($Script:CliTipsOnly) {
        Write-CliHeader -Name 'Node Templates'
        Write-CliTips @(
            "# List node templates",
            "Get-HpcNodeTemplate -Scheduler $SchedulerNode | Select Name,Type,Priority",
            "# List HPC groups",
            "Get-HpcGroup -Scheduler $SchedulerNode | Select Name,Description"
        )
        return
    }
    Write-Section "NODE TEMPLATES & GROUPS"
    if (Import-HpcModule -Quiet) {
        try {
            $nodeTemplates = Get-HpcNodeTemplate -Scheduler $SchedulerNode -ErrorAction SilentlyContinue
            $nodeGroups    = Get-HpcGroup -Scheduler $SchedulerNode -ErrorAction SilentlyContinue

            $tCount = if ($nodeTemplates) { $nodeTemplates.Count } else { 0 }
            $gCount = if ($nodeGroups) { $nodeGroups.Count } else { 0 }
            Write-Host ("  Templates: {0} | Groups: {1}" -f $tCount, $gCount) -ForegroundColor White

            if ($VerbosePreference -eq 'Continue') {
                if ($nodeTemplates -and $nodeTemplates.Count -gt 0) {
                    Write-Host ""; Write-Host "Available Node Templates:" -ForegroundColor Green
                    $templateFormat = "{0,-20} {1,-15} {2,-10} {3,-40}"
                    Write-Host ($templateFormat -f "TEMPLATE NAME", "TYPE", "PRIORITY", "DESCRIPTION") -ForegroundColor White
                    Write-Host ("-" * 90) -ForegroundColor White
                    foreach ($template in ($nodeTemplates | Sort-Object Name)) {
                        $name  = [string]$template.Name
                        $type  = if ($template.PSObject.Properties['Type']) { [string]$template.Type } else { '' }
                        $prio  = if ($template.PSObject.Properties['Priority'] -and $template.Priority) { [string]$template.Priority } else { 'Default' }
                        $desc  = if ($template.PSObject.Properties['Description'] -and $template.Description) { [string]$template.Description } else { 'No description' }
                        if ($desc.Length -gt 38) { $desc = $desc.Substring(0,38) + '...' }
                        Write-Host ($templateFormat -f $name, $type, $prio, $desc) -ForegroundColor White
                    }
                } else {
                    Write-Host "  No node templates found" -ForegroundColor Yellow
                }

                if ($nodeGroups -and $nodeGroups.Count -gt 0) {
                    Write-Host ""; Write-Host "Node Groups:" -ForegroundColor Green
                    foreach ($group in ($nodeGroups | Sort-Object Name)) {
                        $memberCount = 0
                        if ($group.PSObject.Properties['Nodes'] -and $group.Nodes) { $memberCount = $group.Nodes.Count }
                        elseif ($group.PSObject.Properties['Members'] -and $group.Members) { $memberCount = $group.Members.Count }
                        $gdesc = if ($group.PSObject.Properties['Description'] -and $group.Description) { [string]$group.Description } else { '' }
                        if ($gdesc -and $gdesc.Length -gt 60) { $gdesc = $gdesc.Substring(0,57) + '...' }
                        Write-Host ("   Group: {0} | Members: {1} | Description: {2}" -f $group.Name, $memberCount, $gdesc) -ForegroundColor White
                    }
                } else {
                    Write-Host "  No node groups found" -ForegroundColor Yellow
                }
            }
        } catch {}

    } else {
        Write-Host "  ⚠️  HPC module not available" -ForegroundColor Yellow
    }
}

function Invoke-JobHistory {
    if ($Script:CliTipsOnly) {
        Write-CliHeader -Name 'Job History'
        Write-CliTips @(
            '# Job details',
            'Get-HpcJob -Id <JobId> -Scheduler <SchedulerNode>; Get-HpcTask -JobId <JobId> -Scheduler <SchedulerNode>'
            "# Show last 20 jobs (table)",
            "Get-HpcJob -Scheduler $SchedulerNode -State All | Sort-Object SubmitTime -Descending | Select-Object -First 20 | Format-Table Id,Name,State,Owner,SubmitTime -Auto",
            "# Job details: Get-HpcJob -Id <JobId> -Scheduler $SchedulerNode; Get-HpcTask -JobId <JobId> -Scheduler $SchedulerNode"
        )
        return
    }
    Write-Section "JOB HISTORY"
    if (Import-HpcModule -Quiet) {
        try {
            $currentJobs = Get-HpcJob -State All -Scheduler $SchedulerNode -ErrorAction SilentlyContinue |
                           Sort-Object SubmitTime -Descending |
                           Select-Object -First 20

            if ($currentJobs) {
                Write-Host ("  Jobs: {0} (showing 20)" -f $currentJobs.Count) -ForegroundColor White
                # Concise default view: first 5 jobs
                $currentJobs | Select-Object -First 5 | ForEach-Object {
                    Write-Host ("   #{0} {1} [{2}]" -f $_.Id, $_.Name, $_.State) -ForegroundColor Gray
                }

                if ($VerbosePreference -eq 'Continue') {
                    # Statistics for the last 20 jobs
                    $jobStats = @{
                        Total    = $currentJobs.Count
                        Running  = ($currentJobs | Where-Object { $_.State -eq 'Running' }).Count
                        Queued   = ($currentJobs | Where-Object { $_.State -eq 'Queued' }).Count
                        Finished = ($currentJobs | Where-Object { $_.State -eq 'Finished' }).Count
                        Failed   = ($currentJobs | Where-Object { $_.State -eq 'Failed' }).Count
                        Canceled = ($currentJobs | Where-Object { $_.State -eq 'Canceled' }).Count
                    }

                    Write-Host ""; Write-Host "Current Job Statistics (Last 20 jobs):" -ForegroundColor Green
                    Write-Host ("   Total Jobs...........: {0}" -f $jobStats.Total) -ForegroundColor White
                    Write-Host ("   Running Jobs.........: {0}" -f $jobStats.Running) -ForegroundColor White
                    Write-Host ("   Queued Jobs..........: {0}" -f $jobStats.Queued) -ForegroundColor White
                    Write-Host ("   Finished Jobs........: {0}" -f $jobStats.Finished) -ForegroundColor White
                    Write-Host ("   Failed Jobs..........: {0}" -f $jobStats.Failed) -ForegroundColor White
                    Write-Host ("   Canceled Jobs........: {0}" -f $jobStats.Canceled) -ForegroundColor White

                    # Recent jobs table (top 5 by submit time)
                    $recentJobs = $currentJobs | Select-Object -First 5
                    if ($recentJobs) {
                        Write-Host ""; Write-Host "Recent Jobs:" -ForegroundColor Green
                        $jobFormat = "{0,-8} {1,-12} {2,-15} {3,-20}"
                        Write-Host ($jobFormat -f "JOB ID", "STATE", "OWNER", "NAME") -ForegroundColor White
                        Write-Host ("-" * 60) -ForegroundColor White
                        foreach ($job in $recentJobs) {
                            $nm = [string]$job.Name
                            if ($nm -and $nm.Length -gt 18) { $nm = $nm.Substring(0,18) + '...' }
                            Write-Host ($jobFormat -f $job.Id, $job.State, $job.Owner, $nm) -ForegroundColor White
                        }
                    }

                    # Job templates (top 10)
                    try {
                        if (Get-Command Get-HpcJobTemplate -ErrorAction SilentlyContinue) {
                            $jobTemplates = Get-HpcJobTemplate -Scheduler $SchedulerNode -ErrorAction SilentlyContinue
                            if ($jobTemplates) {
                                Write-Host ""; Write-Host "Available Job Templates:" -ForegroundColor Green
                                foreach ($template in ($jobTemplates | Sort-Object Name | Select-Object -First 10)) {
                                    $tType = if ($template.PSObject.Properties['Type']) { $template.Type } else { '' }
                                    Write-Host ("   Template: {0} | Type: {1}" -f $template.Name, $tType) -ForegroundColor White
                                }
                            }
                        }
                    } catch {}
                }
            } else {
                Write-Host "  No jobs found in queue" -ForegroundColor Yellow
            }

            # Optional: Node history printing
            try {
                if ($NodeName) {
                    Invoke-NodeHistory -NodeName $NodeName -DaysBack $DaysBack
                } elseif ($JobId -gt 0) {
                    # Infer a node from the job if possible (finished/running jobs)
                    try {
                        $j = Get-HpcJob -Id $JobId -Scheduler $SchedulerNode -ErrorAction SilentlyContinue
                        $nodeGuess = $null
                        if ($j -and $j.PSObject.Properties['AllocatedNodes'] -and $j.AllocatedNodes -and $j.AllocatedNodes.Count -gt 0) {
                            $nodeGuess = $j.AllocatedNodes[0].NetBiosName
                        }
                        if ($nodeGuess) { Invoke-NodeHistory -NodeName $nodeGuess -DaysBack $DaysBack }
                    } catch {}
                }
            } catch {}
        } catch {}
    } else {
        Write-Host "  ⚠️  HPC module not available" -ForegroundColor Yellow
    }

}
 

function Get-HpcJobDetails {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [int]$JobId
    )

    if (-not (Import-HpcModule -Quiet)) {
        Write-Warning "❌ HPC module not available; cannot query job details."
        return $null
    }

    try {
        $job = Get-HpcJob -Id $JobId -Scheduler $SchedulerNode -ErrorAction Stop
    $tasks = @()
    try { $tasks = Get-HpcTask -JobId $JobId -Scheduler $SchedulerNode -ErrorAction SilentlyContinue } catch { $tasks = @() }

        $nodeCount = 0
        if ($job -and $job.PSObject.Properties['AllocatedNodes'] -and $job.AllocatedNodes) { $nodeCount = $job.AllocatedNodes.Count }

        # Normalize tasks as an array of projected objects
        $taskList = @()
        if ($tasks) { $taskList = @($tasks | Select-Object Id, Name, CommandLine, State, ExitCode, ErrorMessage) }

        return [PSCustomObject]@{
            JobId      = $job.Id
            Name       = $job.Name
            Owner      = $job.Owner
            State      = $job.State
            SubmitTime = $job.SubmitTime
            StartTime  = $job.StartTime
            EndTime    = $job.EndTime
            NodeCount  = $nodeCount
            TaskCount  = if ($taskList) { $taskList.Count } else { 0 }
            Tasks      = $taskList
        }
    } catch {
        Write-Warning ("❌ Could not retrieve job details for JobId {0}: {1}" -f $JobId, $_)
        return $null
    }
}

function Invoke-ClusterMetrics {
    if ($Script:CliTipsOnly) {
        Write-CliHeader -Name 'Cluster Metrics'
        Write-CliTips @(
            '# Get cluster metrics',
            "Get-HpcMetric -Scheduler $SchedulerNode",
            '# Example: Get metric values for a node',
            "Get-HpcMetricValue -Scheduler $SchedulerNode -MetricName HPCCpuUsage -NodeName <NodeName>"
        )
        return
    }
    Write-Section "CLUSTER METRICS"
    if (Import-HpcModule -Quiet) {
        try {
            $m = Get-HpcMetric -Scheduler $SchedulerNode -ErrorAction SilentlyContinue
            if ($m) {
                Write-Host "  Available metrics: $($m.Count)" -ForegroundColor White

                if ($VerbosePreference -eq 'Continue') {
                    Write-Host ""; Write-Host "Available Performance Metrics:" -ForegroundColor Green
                    $criticalMetrics = $m | Where-Object { $_.Name -match 'CPU|Memory|Network|Disk' } | Select-Object -First 8
                    foreach ($metric in $criticalMetrics) {
                        $unit = if ($metric.PSObject.Properties['Unit']) { $metric.Unit } else { '' }
                        $cat  = if ($metric.PSObject.Properties['Category']) { $metric.Category } else { '' }
                        Write-Host ("   Metric: {0} | Unit: {1} | Category: {2}" -f $metric.Name, $unit, $cat) -ForegroundColor White
                    }

                    Write-Host ""; Write-Host "Current Metric Values:" -ForegroundColor Green
                    # Prefer node-scoped metrics first, then cluster-scoped, then category match
                    $cpuMetric = @(
                        ($m | Where-Object { $_.Name -eq 'HPCCpuUsage' }),
                        ($m | Where-Object { $_.Name -eq 'HPCClusterCpu' }),
                        ($m | Where-Object { $_.Name -match 'Cpu' -or ($_.Category -match 'Processor') })
                    ) | Where-Object { $_ } | Select-Object -First 1
                    $memMetric = @(
                        ($m | Where-Object { $_.Name -eq 'HPCFreeMemory' -or $_.Name -eq 'HPCMemory' }),
                        ($m | Where-Object { $_.Name -match 'Memory' -or ($_.Category -match 'Memory') })
                    ) | Where-Object { $_ } | Select-Object -First 1
                    $netMetric = @(
                        ($m | Where-Object { $_.Name -eq 'HPCClusterNetwork' }),
                        ($m | Where-Object { $_.Name -match 'Network' -or ($_.Category -match 'Network') })
                    ) | Where-Object { $_ } | Select-Object -First 1

                    $nodeObj = $null
                    try { $nodeObj = Get-HpcNode -Scheduler $SchedulerNode -Name $env:COMPUTERNAME -ErrorAction SilentlyContinue | Select-Object -First 1 } catch { $nodeObj = $null }

                    function _GetMetricValue([object]$metric){
                        if (-not $metric) { return $null }
                        try {
                            if ($metric.Name -match '^HPCCluster') {
                                return Get-HpcMetricValue -Name $metric.Name -Scheduler $SchedulerNode -ErrorAction SilentlyContinue
                            } elseif ($nodeObj) {
                                return Get-HpcMetricValue -Name $metric.Name -Node $nodeObj -Scheduler $SchedulerNode -ErrorAction SilentlyContinue
                            } else { return $null }
                        } catch { return $null }
                    }

                    $pairs = @(
                        @{ Label = '% Processor Time'; Metric = $cpuMetric; Counter = '\\Processor(_Total)\\% Processor Time' },
                        @{ Label = 'Available MBytes'; Metric = $memMetric; Counter = '\\Memory\\Available MBytes' },
                        @{ Label = 'Bytes Total/sec';  Metric = $netMetric; Counter = '\\Network Interface(*)\\Bytes Total/sec' }
                    )

                    foreach ($p in $pairs) {
                        $label = $p.Label
                        $mvObj = _GetMetricValue -metric $p.Metric
                        $printed = $false
                        if ($mvObj) {
                            $mv = $null; $mu = ''
                            if ($mvObj.PSObject.Properties['Value']) { $mv = $mvObj.Value }
                            elseif ($mvObj.PSObject.Properties['Values']) { $mv = ($mvObj.Values | Select-Object -First 1) }
                            if ($mvObj.PSObject.Properties['Unit']) { $mu = $mvObj.Unit }
                            if ($null -ne $mv -and $mv -ne '') {
                                Write-Host ("   {0}: {1} {2}" -f $label, $mv, $mu) -ForegroundColor White
                                $printed = $true
                            }
                        }
                        if (-not $printed) {
                            # Fallback to local counters with resilient paths
                            try {
                                if ($label -eq '% Processor Time') {
                                    # CPU percent is more reliable with 2 samples
                                    $ctr = Get-Counter $p.Counter -SampleInterval 1 -MaxSamples 2 -ErrorAction SilentlyContinue
                                    if ($ctr -and $ctr.CounterSamples) {
                                        $last = $ctr.CounterSamples | Select-Object -Last 1
                                        $val = if ($null -ne $last.CookedValue) { [math]::Round([double]$last.CookedValue, 2) } else { $null }
                                        if ($null -ne $val) { Write-Host ("   {0}: {1}" -f $label, $val) -ForegroundColor White } else { throw 'no cpu sample' }
                                    } else { throw 'no cpu counters' }
                                } elseif ($label -eq 'Available MBytes') {
                                    $ctr = Get-Counter $p.Counter -SampleInterval 1 -MaxSamples 1 -ErrorAction SilentlyContinue
                                    if ($ctr -and $ctr.CounterSamples) {
                                        $avg = ($ctr.CounterSamples | Measure-Object -Property CookedValue -Average).Average
                                        $val = if ($null -ne $avg) { [math]::Round([double]$avg, 2) } else { $null }
                                        if ($null -ne $val) { Write-Host ("   {0}: {1}" -f $label, $val) -ForegroundColor White } else { throw 'no mem sample' }
                                    } else {
                                        # Fallback to CIM if perf counter not available
                                        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
                                        if ($os -and $os.FreePhysicalMemory) {
                                            $mb = [math]::Round(([double]$os.FreePhysicalMemory/1024),2)
                                            Write-Host ("   {0}: {1}" -f $label, $mb) -ForegroundColor White
                                        } else { throw 'no cim mem' }
                                    }
                                } elseif ($label -eq 'Bytes Total/sec') {
                                    $ctr = Get-Counter $p.Counter -SampleInterval 1 -MaxSamples 1 -ErrorAction SilentlyContinue
                                    if ($ctr -and $ctr.CounterSamples) {
                                        $avg = ($ctr.CounterSamples | Measure-Object -Property CookedValue -Average).Average
                                        $val = if ($null -ne $avg) { [math]::Round([double]$avg, 3) } else { $null }
                                        if ($null -ne $val) { Write-Host ("   {0}: {1}" -f $label, $val) -ForegroundColor White } else { Write-Host ("   {0}: [n/a]" -f $label) -ForegroundColor Yellow }
                                    } else { Write-Host ("   {0}: [n/a]" -f $label) -ForegroundColor Yellow }
                                } else {
                                    # Generic fallback
                                    $ctr = Get-Counter $p.Counter -SampleInterval 1 -MaxSamples 1 -ErrorAction SilentlyContinue
                                    if ($ctr -and $ctr.CounterSamples) {
                                        $avg = ($ctr.CounterSamples | Measure-Object -Property CookedValue -Average).Average
                                        $val = if ($null -ne $avg) { [math]::Round([double]$avg, 2) } else { $null }
                                        if ($null -ne $val) { Write-Host ("   {0}: {1}" -f $label, $val) -ForegroundColor White } else { Write-Host ("   {0}: [n/a]" -f $label) -ForegroundColor Yellow }
                                    } else { Write-Host ("   {0}: [n/a]" -f $label) -ForegroundColor Yellow }
                                }
                            } catch { Write-Host ("   {0}: [n/a]" -f $label) -ForegroundColor Yellow }
                        }
                    }
                }
            } else {
                Write-Host "  No performance metrics available" -ForegroundColor Yellow
            }
        } catch {}
    } else {
        Write-Host "  ⚠️  HPC module not available" -ForegroundColor Yellow
    }

}

# SQL trace readiness and guidance (top-level for dispatcher)
function Invoke-SqlTrace {
    if ($Script:CliTipsOnly) {
        Write-CliHeader -Name 'SQL Trace'
        Write-CliTips @(
            '# Extract SQL instance from HPC registry',
            "(Get-ItemProperty 'HKLM:\\SOFTWARE\\Microsoft\\HPC\\Security').HAStorageDbConnectionString",
            '# Run quick collector (creates HPC_QuickTrace.xel next to the script)',
            '.\sql-trace-collector.ps1',
            '# Analyze the trace (events/sec, p50/p95/p99, top apps)',
            '.\sql-trace-analyzer.ps1'
        )
        return
    }

    Write-Section 'SQL TRACE READINESS'
    try {
        $regPath = 'HKLM:\SOFTWARE\Microsoft\HPC\Security'
        $valName = 'HAStorageDbConnectionString'
        $connectionString = (Get-ItemProperty -Path $regPath -ErrorAction Stop).$valName
        if (-not $connectionString) {
            Write-Host "  ❌ Connection string not found at $regPath ($valName)" -ForegroundColor Red
            return
        }
        $serverName = $null
        if ($connectionString -match 'Data Source=([^;]+)') { $serverName = $matches[1] }
        if ($serverName) {
            Write-Host ("  ✅ SQL Server instance: {0}" -f $serverName) -ForegroundColor Green
        } else {
            Write-Host '  ❌ Could not parse Data Source from connection string' -ForegroundColor Red
        }

        # Probe SQL edition and version (trust server certificate for quick diagnostics)
        try {
            $csb = New-Object System.Data.SqlClient.SqlConnectionStringBuilder $connectionString
            $csb.TrustServerCertificate = $true
            $trustedConnectionString = $csb.ConnectionString

            $query = "SELECT SERVERPROPERTY('Edition') AS Edition, SERVERPROPERTY('ProductVersion') AS Version"
            $connection = New-Object System.Data.SqlClient.SqlConnection $trustedConnectionString
            $command = $connection.CreateCommand()
            $command.CommandText = $query

            $connection.Open()
            $reader = $command.ExecuteReader()
            if ($reader.Read()) {
                Write-Host ("  🧠 Edition: {0}" -f $reader['Edition']) -ForegroundColor White
                Write-Host ("  📦 Version: {0}" -f $reader['Version']) -ForegroundColor White
            }
            $reader.Close()
            $connection.Close()
        } catch {
            Write-Host ("  ⚠️  SQL query failed: {0}" -f $_) -ForegroundColor Yellow
        }

        Write-Host ''
        Write-Host 'Next steps for detailed SQL trace:' -ForegroundColor Yellow
        Write-Host '  1) Run the collector to create HPC_QuickTrace.xel:' -ForegroundColor White
        Write-Host '     .\sql-trace-collector.ps1' -ForegroundColor Cyan
        Write-Host '  2) Analyze results with percentiles and throughput:' -ForegroundColor White
        if ($serverName) {
            Write-Host ("     .\sql-trace-analyzer.ps1 -ServerInstance '{0}' -XeFile .\HPC_QuickTrace.xel" -f $serverName) -ForegroundColor Cyan
        } else {
            Write-Host "     .\sql-trace-analyzer.ps1 -ServerInstance <server> -XeFile .\\HPC_QuickTrace.xel" -ForegroundColor Cyan
        }
    } catch {
        Write-Host ("  ⚠️  SQL trace readiness failed: {0}" -f $_.Exception.Message) -ForegroundColor Yellow
    }
}

function Invoke-MetricValueHistory {
    [CmdletBinding()]
    param(
        [datetime]$StartDate = (Get-Date).AddDays(-7),
        [datetime]$EndDate = (Get-Date),
        [string]$OutputPath = 'MetricValueHistory.csv'
    )

    Write-Section "METRIC VALUE HISTORY"
    if (-not (Import-HpcModule -Quiet)) { Write-Host "  ❌ HPC module not available" -ForegroundColor Red; return }

    if ($Script:CliTipsOnly) {
        Write-CliHeader -Name 'Metric Value History'
        Write-CliTips @(
            '# Export last 7 days of metric value history to CSV',
            '$startDate = (Get-Date).AddDays(-7)',
            '$endDate = Get-Date',
            'Get-HpcMetricValueHistory -StartDate $startDate -EndDate $endDate | Export-Csv -Path "MetricValueHistory.csv" -NoTypeInformation',
            '# Export a specific date range to a custom path',
            "$startDate = Get-Date '2025-08-01'",
            "$endDate = Get-Date '2025-08-14'",
            'Get-HpcMetricValueHistory -StartDate $startDate -EndDate $endDate | Export-Csv -Path "C:\\temp\\MetricValueHistory.csv" -NoTypeInformation'
        )
        return
    }

    try {
        $rows = Get-HpcMetricValueHistory -Scheduler $SchedulerNode -StartDate $StartDate -EndDate $EndDate -ErrorAction Stop
    } catch {
        Write-Host ("  ❌ Get-HpcMetricValueHistory failed: {0}" -f $_.Exception.Message) -ForegroundColor Red
        return
    }

    $count = @($rows).Count
    Write-Host ("  Rows returned: {0}" -f $count) -ForegroundColor White
    if ($count -gt 0) {
        try {
            $fullPath = if ([System.IO.Path]::IsPathRooted($OutputPath)) { $OutputPath } else { Join-Path -Path (Get-Location) -ChildPath $OutputPath }
            $parent = Split-Path -Path $fullPath -Parent
            if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -Path $parent -ItemType Directory -Force | Out-Null }
            $rows | Export-Csv -Path $fullPath -NoTypeInformation -Encoding UTF8
            Write-Host ("  ✅ Exported to: {0}" -f $fullPath) -ForegroundColor Green
        } catch {
            Write-Host ("  ❌ Export failed: {0}" -f $_.Exception.Message) -ForegroundColor Red
        }
        if ($VerbosePreference -eq 'Continue') {
            # Show a small preview in verbose mode
            $preview = $rows | Select-Object -First 5
            if ($preview) {
                Write-Host ""; Write-Host "Preview (first 5 rows):" -ForegroundColor Green
                $preview | Format-Table -AutoSize | Out-String -Width 200 | ForEach-Object { $_.TrimEnd() } | Write-Host
            }
        }
    }
}

function Invoke-ClusterTopology {
    if ($Script:CliTipsOnly) {
        Write-CliHeader -Name 'Cluster Topology'
        Write-CliTips @(
            '# Role counts and reachability',
            'Get-HpcNode -Scheduler <SchedulerNode> | Group-Object NodeRole | Select Name,Count'
        )
        return
    }
    Write-Section "CLUSTER TOPOLOGY & NODE ANALYSIS"
    if (Import-HpcModule -Quiet) {
        try {
            $hpcNodes = Get-HpcNode -Scheduler $SchedulerNode -ErrorAction SilentlyContinue
            if ($hpcNodes) {
                if ($VerbosePreference -eq 'Continue') {
                    # Detailed view (summary + table)
                    $total      = $hpcNodes.Count
                    $online     = ($hpcNodes | Where-Object { $_.NodeState -eq 'Online' }).Count
                    $offline    = ($hpcNodes | Where-Object { $_.NodeState -eq 'Offline' }).Count
                    $unknown    = ($hpcNodes | Where-Object { $_.NodeState -eq 'Unknown' }).Count
                    $healthy    = ($hpcNodes | Where-Object { $_.HealthState -eq 'OK' }).Count
                    $unhealthy  = ($hpcNodes | Where-Object { $_.HealthState -ne 'OK' }).Count

                    function Get-RoleCount([object[]]$nodes,[string]$roleName){
                        $pattern = switch ($roleName) {
                            'HeadNode'    { '(?i)Head|\bHN\b' }
                            'ComputeNode' { '(?i)Compute|\bCN\b' }
                            'BrokerNode'  { '(?i)Broker|\bBN\b' }
                            default       { [regex]::Escape($roleName) }
                        }
                        ($nodes | Where-Object {
                            $isMatch = $false
                            if ($_.PSObject.Properties['NodeRole'] -and $_.NodeRole) {
                                $roleStr = ("{0}" -f ($_.NodeRole -join ','))
                                if ($roleStr -match $pattern) { $isMatch = $true }
                            }
                            if (-not $isMatch -and $_.PSObject.Properties['NodeType'] -and $_.NodeType) {
                                if (("{0}" -f $_.NodeType) -match $pattern) { $isMatch = $true }
                            }
                            if (-not $isMatch -and $roleName -eq 'HeadNode') {
                                if ($_.NetBiosName -and $SchedulerNode -and ("$($_.NetBiosName)" -ieq "$SchedulerNode")) { $isMatch = $true }
                            }
                            return $isMatch
                        }).Count
                    }

                    $headNodes    = Get-RoleCount -nodes $hpcNodes -roleName 'HeadNode'
                    $computeNodes = Get-RoleCount -nodes $hpcNodes -roleName 'ComputeNode'
                    $brokerNodes  = Get-RoleCount -nodes $hpcNodes -roleName 'BrokerNode'

                    $totalCores = 0
                    foreach ($n in $hpcNodes) {
                        $coreVal = $null
                        foreach ($p in 'ProcessorCores','NumberOfCores','Cores') {
                            if ($n.PSObject.Properties[$p] -and $n.$p) { $coreVal = [int]$n.$p; break }
                        }
                        if ($coreVal) { $totalCores += $coreVal }
                    }

                    Write-Host "Cluster Summary:" -ForegroundColor Green
                    Write-Host ("   Total Nodes..........: {0}" -f $total) -ForegroundColor White
                    Write-Host ("   Online Nodes.........: {0}" -f $online) -ForegroundColor White
                    Write-Host ("   Offline Nodes........: {0}" -f $offline) -ForegroundColor White
                    Write-Host ("   Unknown State........: {0}" -f $unknown) -ForegroundColor White
                    Write-Host ("   Healthy Nodes........: {0}" -f $healthy) -ForegroundColor White
                    Write-Host ("   Unhealthy Nodes......: {0}" -f $unhealthy) -ForegroundColor White
                    Write-Host ("   Head Nodes...........: {0}" -f $headNodes) -ForegroundColor White
                    Write-Host ("   Compute Nodes........: {0}" -f $computeNodes) -ForegroundColor White
                    Write-Host ("   Broker Nodes.........: {0}" -f $brokerNodes) -ForegroundColor White
                    Write-Host ("   Total CPU Cores......: {0}" -f $totalCores) -ForegroundColor White
                    Write-Host ""

                    Write-Host "Detailed Node Information:" -ForegroundColor Green
                    $fmt = "{0,-15} {1,-10} {2,-10} {3,-15} {4,-8} {5,-12} {6,-15}"
                    Write-Host ($fmt -f 'NAME','STATE','HEALTH','TEMPLATE','CORES','MEMORY(GB)','NETWORK') -ForegroundColor White
                    Write-Host ("-"*95) -ForegroundColor White

                    foreach ($node in $hpcNodes | Sort-Object NetBiosName) {
                        $template = if ($node.PSObject.Properties['NodeTemplate'] -and $node.NodeTemplate) { "$($node.NodeTemplate)" } else { 'Default' }

                        $coresVal = $null
                        foreach ($p in 'ProcessorCores','NumberOfCores','Cores') {
                            if ($node.PSObject.Properties[$p] -and $node.$p) { $coresVal = [string]$node.$p; break }
                        }
                        if (-not $coresVal) { $coresVal = 'N/A' }

                        $memGB = $null
                        $memMB = $null
                        foreach ($mp in 'Memory','MemoryMB','TotalMemoryMB') {
                            if ($node.PSObject.Properties[$mp] -and $node.$mp) { $memMB = [double]$node.$mp; break }
                        }
                        if ($memMB) { $memGB = [math]::Round($memMB/1024,1) } else { $memGB = 'N/A' }

                        $networkStatus = 'Unknown'
                        try {
                            $ping = Test-Connection -ComputerName $node.NetBiosName -Count 1 -Quiet -ErrorAction SilentlyContinue
                            $networkStatus = if ($ping) { 'Reachable' } else { 'Unreachable' }
                        } catch { $networkStatus = 'Test Failed' }

                        Write-Host ($fmt -f $node.NetBiosName, $node.NodeState, $node.HealthState, $template, $coresVal, $memGB, $networkStatus) -ForegroundColor White
                    }
                }
                else {
                    # Concise view (first 5 nodes reachability/state/health)
                    $sample = $hpcNodes | Select-Object -First 5
                    foreach ($n in $sample) {
                        $ok = $false
                        try { $ok = Test-Connection -ComputerName $n.NetBiosName -Count 1 -Quiet -ErrorAction SilentlyContinue } catch {}
                        Write-Host ("  {0}: Reachable={1} State={2} Health={3}" -f $n.NetBiosName, $ok, $n.NodeState, $n.HealthState) -ForegroundColor White
                    }
                }
            }
            else {
                Write-Host "  No HPC nodes found in cluster" -ForegroundColor Yellow
            }
        } catch {
            Write-Host ("  Could not retrieve HPC node information: {0}" -f $_.Exception.Message) -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "  ⚠️  HPC module not available" -ForegroundColor Yellow
    }
}

function Invoke-ServicesStatus {
    if ($Script:CliTipsOnly) {
        Write-CliHeader -Name 'Services Status'
        Write-CliTips @(
            '# HPC/MPI/SQL service states',
            'Get-Service | Where-Object { $_.DisplayName -like "*HPC*" -or $_.DisplayName -like "*MPI*" -or $_.DisplayName -like "*SQL*" }',
            "# Include StartMode via CIM (used for summary)",
            'Get-CimInstance Win32_Service | Where-Object { $_.DisplayName -like "*HPC*" -or $_.DisplayName -like "*MPI*" -or $_.DisplayName -like "*SQL*" } | Sort-Object DisplayName'
        )
        return
    }
    Write-Section "SERVICES STATUS (HPC/MPI/SQL)"
    # Use CIM to include StartMode for summary details
    $svcs = Get-CimInstance -ClassName Win32_Service -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like '*HPC*' -or $_.DisplayName -like '*MPI*' -or $_.DisplayName -like '*SQL*' } |
        Sort-Object DisplayName
    if (-not $svcs) { Write-Host "  ⚠️  No HPC/MPI/SQL services found" -ForegroundColor Yellow; return }

    $total   = $svcs.Count
    $running = ($svcs | Where-Object { $_.State -eq 'Running' }).Count
    $stopped = ($svcs | Where-Object { $_.State -ne 'Running' }).Count
    $auto    = ($svcs | Where-Object { $_.StartMode -match 'Auto' }).Count
    $manual  = ($svcs | Where-Object { $_.StartMode -match 'Manual' }).Count
    $disabled= ($svcs | Where-Object { $_.StartMode -match 'Disabled' }).Count

    Write-Host "Service Summary:" -ForegroundColor Green
    Write-Host ("   Total Services.......: {0}" -f $total) -ForegroundColor White
    Write-Host ("   Running Services.....: {0}" -f $running) -ForegroundColor White
    Write-Host ("   Stopped Services.....: {0}" -f $stopped) -ForegroundColor White
    Write-Host ("   Automatic Start......: {0}" -f $auto) -ForegroundColor White
    Write-Host ("   Manual Start.........: {0}" -f $manual) -ForegroundColor White
    Write-Host ("   Disabled.............: {0}" -f $disabled) -ForegroundColor White

    Write-Host ""; Write-Host "Service Details:" -ForegroundColor Green
    $headerFmt = "{0,-35} {1,-9} {2,-12}"
    Write-Host ($headerFmt -f 'SERVICE NAME','STATUS','START TYPE') -ForegroundColor White
    Write-Host ('-'*60) -ForegroundColor White
    foreach ($s in $svcs) {
        $status = $s.State
        $start  = switch -regex ($s.StartMode) { 'Auto' { 'Automatic'; break } 'Manual' { 'Manual'; break } 'Disabled' { 'Disabled'; break } default { $s.StartMode } }
        Write-Host ($headerFmt -f $s.DisplayName, $status, $start) -ForegroundColor White
    }
}

function Invoke-DiagnosticTests {
    if ($Script:CliTipsOnly) {
        Write-CliHeader -Name 'Diagnostic Tests'
        Write-CliTips @(
            '# Run built-in HPC Pack diagnostic tests',
            'Get-HpcTest -Scheduler <SchedulerNode> -TestName <TestName>'
            '# Check current TrustedHosts',
            'Get-Item WSMan:\localhost\Client\TrustedHosts',
            '# Add node to TrustedHosts (overwrites existing value)',
            'Set-Item WSMan:\localhost\Client\TrustedHosts -Value "<NodeName>" -Force',
            '# Append node to TrustedHosts (safer)',
            'Set-Item WSMan:\localhost\Client\TrustedHosts -Value "<NodeName>" -Concatenate -Force'
        )
        return
    }
    Write-Section "DIAGNOSTIC TESTS"
    if (Import-HpcModule -Quiet) {
        try {
            $tests = Get-HpcTest -Scheduler $SchedulerNode -ErrorAction SilentlyContinue
            if ($tests) { Write-Host "  Available tests: $($tests.Count)" -ForegroundColor White }
        } catch { }
    }
    $ccp = [Environment]::GetEnvironmentVariable('CCP_HOME','Machine')
    if ($ccp) {
        $exe = Join-Path $ccp 'Bin\HpcDiagnosticHost.exe'
        if (Test-Path $exe) {
            try {
                $certOutput = & $exe runstep certtest -duration:10 2>&1
                $exitCode = $LASTEXITCODE
                if ($VerbosePreference -eq 'Continue') {
                    Write-Host "  --- Cert test raw output ---" -ForegroundColor DarkGray
                    $certOutput | ForEach-Object { Write-Host ("    " + $_) -ForegroundColor DarkGray }
                }
                $joined = ($certOutput | Out-String)
                $status = 'Unknown'
                if ($exitCode -eq 0 -or $joined -match '(?i)\bpass(ed)?\b') {
                    $status = 'PASS'
                } elseif ($exitCode -ne 0 -or $joined -match '(?i)\bfail(ed)?\b|error') {
                    $status = 'FAIL'
                }
                $color = if ($status -eq 'PASS') { 'Green' } elseif ($status -eq 'FAIL') { 'Red' } else { 'Yellow' }
                Write-Host ("  Cert test: {0} (exit={1})" -f $status,$exitCode) -ForegroundColor $color
                if ($status -ne 'PASS' -and $certOutput) {
                    Write-Host "  Tail (last 5 lines):" -ForegroundColor Yellow
                    $certOutput | Select-Object -Last 5 | ForEach-Object { Write-Host ("    " + $_) -ForegroundColor Yellow }
                }
            } catch {
                Write-Host "  Cert test failed" -ForegroundColor Yellow
            }
            
            # Under -Verbose, also show WSMan TrustedHosts and suggest adding unhealthy nodes
            if ($VerbosePreference -eq 'Continue') {
                Write-Host ""; Write-Host "WSMan TrustedHosts Check:" -ForegroundColor Green
                $trusted = $null
                try {
                    $trusted = (Get-Item -Path WSMan:\localhost\Client\TrustedHosts -ErrorAction SilentlyContinue).Value
                    if ($trusted) { Write-Host ("   TrustedHosts........: {0}" -f $trusted) -ForegroundColor White }
                    else { Write-Host "   TrustedHosts........: (empty)" -ForegroundColor Yellow }
                } catch { Write-Host ("   Could not read TrustedHosts: {0}" -f $_.Exception.Message) -ForegroundColor Yellow }

                try {
                    $unhealthy = $null
                    if (Get-Command Get-HpcNode -ErrorAction SilentlyContinue) {
                        $unhealthy = Get-HpcNode -Scheduler $SchedulerNode -ErrorAction SilentlyContinue |
                                     Where-Object { $_.HealthState -ne 'OK' -or $_.NodeState -ne 'Online' }
                    }
                    $trustedList = @()
                    $hasWildcard = $false
                    if ($trusted) {
                        $trustedList = @($trusted -split ',' | ForEach-Object { $_.Trim() })
                        $hasWildcard = ($trustedList -contains '*')
                    }
                    if ($unhealthy -and -not $hasWildcard) {
                        foreach ($n in $unhealthy) {
                            $name = $n.NetBiosName
                            if (-not $name) { continue }
                            if (-not ($trustedList -contains $name)) {
                                Write-Host ("   Suggest adding {0} to TrustedHosts (on headnode):" -f $name) -ForegroundColor Yellow
                                Write-Host ('     Set-Item WSMan:\localhost\Client\TrustedHosts -Value "{0}" -Force' -f $name) -ForegroundColor Gray
                                Write-Host ('     # Append instead of replacing:') -ForegroundColor DarkGray
                                Write-Host ('     Set-Item WSMan:\localhost\Client\TrustedHosts -Value "{0}" -Concatenate -Force' -f $name) -ForegroundColor DarkGray
                            }
                        }
                    }
                } catch {}
 
            }
        }
    }

    # Pretty validation block similar to requested format
    $bar = '-' * 60
    Write-Host ""; Write-Host "HPC DIAGNOSTIC TESTS & VALIDATION" -ForegroundColor White
    Write-Host $bar -ForegroundColor White
    Write-Host "Running Essential Diagnostic Tests:" -ForegroundColor White

    # Certificate details from registry/thumbprint if available
    $thumb = $null; $expiry = $null; $daysLeft = $null; $certStatusText = 'Unknown'
    try {
        $reg = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\HPC' -ErrorAction SilentlyContinue
        if ($reg -and $reg.SSLThumbprint) { $thumb = ($reg.SSLThumbprint -replace '\s','').ToUpperInvariant() }
    } catch { }
    if (-not $thumb -and (Get-Command Get-HpcInstallCertificate -ErrorAction SilentlyContinue)) {
        try { $ci = Get-HpcInstallCertificate -ErrorAction SilentlyContinue; if ($ci -and $ci.Thumbprint) { $thumb = ($ci.Thumbprint -replace '\s','').ToUpperInvariant() } } catch { }
    }
    $certObj = $null
    if ($thumb) {
        try { $certObj = Get-ChildItem -Path Cert:\LocalMachine\My | Where-Object { ($_.Thumbprint -replace '\s','').ToUpperInvariant() -eq $thumb } | Select-Object -First 1 } catch { }
    }
    if ($certObj) {
        $expiry = $certObj.NotAfter
        $daysLeft = [int]([Math]::Floor(($expiry - (Get-Date)).TotalDays))
        if ($daysLeft -ge 0) { $certStatusText = "[OK] Certificate valid" } else { $certStatusText = "[EXPIRED]" }
    } else {
        $certStatusText = if ($thumb) { "[WARN] Certificate not found in LocalMachine\\My for thumbprint $thumb" } else { "[WARN] Thumbprint not available" }
    }

    # Render certificate section
    Write-Host ("   Certificate Test......:") -ForegroundColor White
    $testResult = if ([string]::IsNullOrEmpty([string]$status)) { 'Unknown' } else { [string]$status }
    Write-Host ("     Test Result.........: {0}" -f $testResult) -ForegroundColor White
    if ($thumb) { Write-Host ("     Thumbprint..........: {0}" -f $thumb) -ForegroundColor White }
    if ($expiry) { Write-Host ("     Expiry Date.........: {0}" -f $expiry) -ForegroundColor White }
    if ($null -ne $daysLeft) { Write-Host ("     Days Until Expiry...: {0}" -f $daysLeft) -ForegroundColor White }
    Write-Host ("     Status..............: {0}" -f $certStatusText) -ForegroundColor White
    if ($certObj) {
        Write-Host ("     SerialNumber........: {0}" -f $certObj.SerialNumber) -ForegroundColor White
        Write-Host ("     NotBefore...........: {0}" -f $certObj.NotBefore) -ForegroundColor White
        Write-Host ("     NotAfter............: {0}" -f $certObj.NotAfter) -ForegroundColor White
        Write-Host ("     HasPrivateKey.......: {0}" -f $certObj.HasPrivateKey) -ForegroundColor White
    }

    # Service configuration summary (complete if all Automatic services are running)
    $svcComplete = $false
    try {
        $svcsCim = Get-CimInstance -ClassName Win32_Service -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like '*HPC*' }
        if ($svcsCim) {
            $autoSvcs = $svcsCim | Where-Object { $_.StartMode -match 'Auto' }
            $allAutoRunning = -not ($autoSvcs | Where-Object { $_.State -ne 'Running' })
            $svcComplete = [bool]$allAutoRunning
        }
    } catch { }
    Write-Host ("   Service Configuration:") -ForegroundColor White
    $svcResult = if ($svcComplete) { 'Complete' } else { 'Issues Detected' }
    Write-Host ("     Result..............: {0}" -f $svcResult) -ForegroundColor White

    # Network connectivity quick checks
    Write-Host ("   Network Connectivity:") -ForegroundColor White
    try {
        $gw4 = (Get-NetRoute -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Sort-Object RouteMetric | Select-Object -First 1).NextHop
        $gw6 = (Get-NetRoute -AddressFamily IPv6 -DestinationPrefix '::/0' -ErrorAction SilentlyContinue | Sort-Object RouteMetric | Select-Object -First 1).NextHop
        $gw = if ($gw4) { $gw4 } elseif ($gw6) { $gw6 } else { $null }
        $gwOk = $false
        if ($gw) { $gwOk = Test-Connection -ComputerName $gw -Count 1 -Quiet -ErrorAction SilentlyContinue }
        $gwVal = if ($gw) { $gw } else { 'n/a' }
        $gwStatus = if ($gwOk) { '[OK]' } else { '[FAIL]' }
        Write-Host ("     Default Gateway.....: {0} {1}" -f $gwVal, $gwStatus) -ForegroundColor White
    } catch { Write-Host ("     Default Gateway.....: [WARN] Error checking") -ForegroundColor Yellow }
    foreach ($hostName in @('microsoft.com','azure.com')) {
        try { Resolve-DnsName $hostName -ErrorAction Stop -Verbose:$false | Out-Null; Write-Host ("     DNS {0,-16}: [OK]" -f $hostName) -ForegroundColor White }
        catch { Write-Host ("     DNS {0,-16}: [FAIL]" -f $hostName) -ForegroundColor White }
    }
}

function Invoke-MpiSmokeTest {
    Write-Section "MPI SMOKE TEST"
    try {
        # Detect Microsoft MPI
        $msmpi = $null
        try { $msmpi = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\MPI' -ErrorAction SilentlyContinue } catch { $msmpi = $null }
        if ($msmpi) {
            $ver = if ($msmpi.PSObject.Properties['Version']) { $msmpi.Version } else { '' }
            Write-Host ("  MPI Runtime..........: Microsoft MPI {0}" -f $ver) -ForegroundColor White
        } else {
            Write-Host "  MPI Runtime..........: Not detected (Microsoft MPI registry not found)" -ForegroundColor Yellow
        }

        # Locate mpiexec
        $mpiexec = Get-Command mpiexec -ErrorAction SilentlyContinue
        if ($mpiexec) {
            Write-Host ("  mpiexec Path.........: {0}" -f $mpiexec.Source) -ForegroundColor White
        } else {
            Write-Host "  mpiexec Path.........: Not found in PATH" -ForegroundColor Yellow
        }

        # Execute simple command if available
        if ($mpiexec) {
            Write-Host "  Running: mpiexec -n 1 hostname" -ForegroundColor Gray
            $out = & $mpiexec.Source -n 1 hostname 2>&1
            $code = $LASTEXITCODE
            $status = if ($code -eq 0) { 'PASS' } else { 'FAIL' }
            $color = if ($code -eq 0) { 'Green' } else { 'Red' }
            Write-Host ("  Result...............: {0} (exit={1})" -f $status,$code) -ForegroundColor $color
            if ($out) { $out | Select-Object -First 5 | ForEach-Object { Write-Host ("    " + $_) -ForegroundColor DarkGray } }

            # Extra diagnostics when -Verbose is provided
            if ($VerbosePreference -eq 'Continue') {
                Write-Host ""; Write-Host "VERBOSE MPI DETAILS" -ForegroundColor Green
                try {
                    # Service status (common candidates: MSMpiSvc, smpd, MSMpiLaunchSvc)
                    $svc = $null
                    $svcName = $null
                    foreach ($name in @('MSMpiSvc','smpd','MSMpiLaunchSvc')) {
                        try { $svc = Get-Service -Name $name -ErrorAction SilentlyContinue } catch { $svc = $null }
                        if ($svc) { $svcName = $name; break }
                    }
                    if ($svc) {
                        $startMode = try { (Get-CimInstance -ClassName Win32_Service -Filter ("Name='" + $svcName + "'") -ErrorAction SilentlyContinue).StartMode } catch { $null }
                        $startModeText = if ($startMode) { $startMode } else { 'Unknown' }
                        Write-Host ("  Service ({0})....: {1} (StartType={2})" -f $svcName, $svc.Status, $startModeText) -ForegroundColor White
                    } else {
                        Write-Host "  Service (MSMPI).......: Not detected" -ForegroundColor Yellow
                    }
                } catch {}

                try {
                    # mpiexec file version
                    $fi = Get-Item -LiteralPath $mpiexec.Source -ErrorAction SilentlyContinue
                    if ($fi -and $fi.VersionInfo) {
                        Write-Host ("  mpiexec Version.......: {0}" -f $fi.VersionInfo.FileVersion) -ForegroundColor White
                    }
                } catch {}

                try {
                    # Environment hints
                    $msmpiBin = $env:MSMPI_BIN; if (-not $msmpiBin -and $msmpi -and $msmpi.PSObject.Properties['InstallRoot']) { $msmpiBin = Join-Path $msmpi.InstallRoot 'Bin' }
                    $msmpiBinText = if ($msmpiBin) { $msmpiBin } else { 'n/a' }
                    Write-Host ("  ENV MSMPI_BIN........: {0}" -f $msmpiBinText) -ForegroundColor White
                    $mpidir = try { [System.IO.Path]::GetDirectoryName($mpiexec.Source) } catch { $null }
                    $inPath = $false
                    try { $inPath = ($env:PATH -split ';' | Where-Object { $_ -and $mpidir -and ("$mpidir" -ieq (($_.TrimEnd('\'))) ) } | Select-Object -First 1) } catch {}
                    Write-Host ("  PATH has mpiexec dir..: {0}" -f ($(if ($inPath) { 'Yes' } else { 'No' }))) -ForegroundColor White
                } catch {}

                # Discover supported options from help and show details conditionally
                $helpOut = $null
                try { $helpOut = & $mpiexec.Source -help 2>&1 } catch { $helpOut = $null }
                if (-not $helpOut) { try { $helpOut = & $mpiexec.Source /? 2>&1 } catch { $helpOut = $null } }

                # mpiexec -info can be noisy; show only if supported
                try {
                    $supportsInfo = $false
                    if ($helpOut) {
                        $txt = ($helpOut | Out-String)
                        if ($txt -match '(?i)(-|/)info') { $supportsInfo = $true }
                    }
                    if ($supportsInfo) {
                        $infoOut = & $mpiexec.Source -info 2>&1
                        if ($infoOut) {
                            Write-Host "  mpiexec -info (first 10 lines):" -ForegroundColor Gray
                            $infoOut | Select-Object -First 10 | ForEach-Object { Write-Host ("    " + $_) -ForegroundColor DarkGray }
                        }
                    } else {
                        Write-Host "  mpiexec -info.........: Skipped (option not supported)" -ForegroundColor DarkGray
                    }
                } catch {}

                # Local-only variant for clarity (if supported)
                try {
                    $supportsLocalOnly = $false
                    if ($helpOut) {
                        $txt2 = ($helpOut | Out-String)
                        if ($txt2 -match '(?i)(-|/)localonly') { $supportsLocalOnly = $true }
                    }
                    if ($supportsLocalOnly) {
                        Write-Host "  Running: mpiexec -localonly -n 1 hostname" -ForegroundColor Gray
                        $out2 = & $mpiexec.Source -localonly -n 1 hostname 2>&1
                        $code2 = $LASTEXITCODE
                        $status2 = if ($code2 -eq 0) { 'PASS' } else { 'FAIL' }
                        $color2 = if ($code2 -eq 0) { 'Green' } else { 'Red' }
                        Write-Host ("  Result (localonly)....: {0} (exit={1})" -f $status2,$code2) -ForegroundColor $color2
                        if ($out2) { $out2 | Select-Object -First 5 | ForEach-Object { Write-Host ("    " + $_) -ForegroundColor DarkGray } }
                    } else {
                        Write-Host "  mpiexec -localonly....: Skipped (option not supported)" -ForegroundColor DarkGray
                    }
                } catch {}
            }
        }
    } catch {
        Write-Host ("  ⚠️  MPI smoke test error: {0}" -f $_.Exception.Message) -ForegroundColor Yellow
    }
}

function Invoke-SystemInfo {
    if ($Script:CliTipsOnly) {
        Write-CliHeader -Name 'System Info'
        Write-CliTips @(
            '# OS version and architecture',
            'Get-CimInstance Win32_OperatingSystem | Select Caption,Version,OSArchitecture',
            '# System manufacturer/model and memory',
            'Get-CimInstance Win32_ComputerSystem | Select Name,Domain,Manufacturer,Model,TotalPhysicalMemory'
        )
        return
    }
    Write-Section "SYSTEM INFORMATION"
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1

        $osName    = $os.Caption
        $osVersion = $os.Version
        $arch      = $os.OSArchitecture
        $ramGB     = [math]::Round(($cs.TotalPhysicalMemory/1GB), 0)
        $lp        = $cs.NumberOfLogicalProcessors
        $domain    = $cs.Domain
        $lastBoot  = $os.LastBootUpTime
        $uptime    = (Get-Date) - $lastBoot
        $uptimeFmt = ("{0:d2}d {1:d2}h {2:d2}m" -f [int]$uptime.Days,[int]$uptime.Hours,[int]$uptime.Minutes)
        $cpuName   = $null; if ($cpu) { $cpuName = if ($cpu.Caption) { $cpu.Caption } else { $cpu.Name } }

        Write-Host "  OS: $osName $osVersion ($arch)" -ForegroundColor White
        Write-Host "  Computer: $($cs.Name) Domain=$domain RAM=$($ramGB)GB" -ForegroundColor White
        if ($lp) { Write-Host ("  LogicalProcessors: {0}" -f $lp) -ForegroundColor White }
        if ($cpuName) { Write-Host ("  CPU: {0}" -f $cpuName) -ForegroundColor White }
        Write-Host ("  Last Boot: {0}" -f $lastBoot) -ForegroundColor White
        Write-Host ("  Uptime: {0}" -f $uptimeFmt) -ForegroundColor White

    if ($VerbosePreference -eq 'Continue') {
            Write-Host ""; Write-Host "SYSTEM INFORMATION" -ForegroundColor White
            Write-Host ("-"*60) -ForegroundColor White
            Write-Host ("Operating System.....: {0}" -f $osName) -ForegroundColor White
            Write-Host ("OS Version...........: {0}" -f $osVersion) -ForegroundColor White
            Write-Host ("Architecture.........: {0}" -f $arch) -ForegroundColor White
            Write-Host ("Total RAM............: {0} GB" -f $ramGB) -ForegroundColor White
            if ($lp) { Write-Host ("Logical Processors...: {0}" -f $lp) -ForegroundColor White }
            Write-Host ("Domain...............: {0}" -f $domain) -ForegroundColor White
            if ($cpuName) { Write-Host ("Processor............: {0}" -f $cpuName) -ForegroundColor White }
            Write-Host ("Last Boot Time.......: {0}" -f $lastBoot) -ForegroundColor White
            Write-Host ("System Uptime........: {0}" -f $uptimeFmt) -ForegroundColor White

            Write-Host ""
            $csLine  = 'ComputerSystem                 Win32_ComputerSystem: {0} (Name = "{0}")' -f $cs.Name
            $osLine  = 'OS                             Win32_OperatingSystem: {0}' -f $osName
            $cpuDisp = if ($cpu -and $cpu.Caption) { $cpu.Caption } elseif ($cpu -and $cpu.Name) { $cpu.Name } else { 'n/a' }
            $cpuLine = 'Processor                      Win32_Processor: {0} (DeviceID = "{1}")' -f $cpuDisp, ($cpu.DeviceID)
            Write-Host $csLine -ForegroundColor White
            Write-Host $osLine -ForegroundColor White
            Write-Host $cpuLine -ForegroundColor White
        }
    } catch {
        Write-Host "  ⚠️  Unable to read system info: $($_.Exception.Message)" -ForegroundColor Yellow
    }
    Write-CliTips @(
        "# OS version and architecture",
        "Get-CimInstance Win32_OperatingSystem | Select Caption,Version,OSArchitecture",
        "# System manufacturer/model and memory",
        "Get-CimInstance Win32_ComputerSystem | Select Name,Domain,Manufacturer,Model,TotalPhysicalMemory"
    )
}

function Invoke-AdvancedHealth {
    if ($Script:CliTipsOnly) {
        Write-CliHeader -Name 'Advanced health checks'
        Write-CliTips @(
            'Get-Counter "\\Processor(_Total)\\% Processor Time"',
            'Get-Counter "\\Memory\\Available MBytes"',
            'Get-Counter "\\Network Interface(*)\\Bytes Total/sec"',
            'Get-NetAdapter | Where-Object { $_.InterfaceDescription -match "InfiniBand|Mellanox|RDMA" }',
            'Get-Service | Where-Object { $_.DisplayName -match "RDMA|NetworkDirect" }',
            'Get-ItemProperty -Path "HKLM:\\SOFTWARE\\Microsoft\\MPI"',
            'Get-ItemProperty -Path "HKLM:\\SOFTWARE\\Microsoft\\HPC"'
        )
        return
    }
    Write-Section "ADVANCED HEALTH"
    try {
        # Concise default summary
        $somethingPrinted = $false
        $cpu = Get-Counter '\\Processor(_Total)\\% Processor Time' -SampleInterval 1 -MaxSamples 1 -ErrorAction SilentlyContinue
        $mem = Get-Counter '\\Memory\\Available MBytes' -SampleInterval 1 -MaxSamples 1 -ErrorAction SilentlyContinue
        if ($cpu) {
            $cpuAvg = ($cpu.CounterSamples | Measure-Object -Property CookedValue -Average).Average
            if ($null -ne $cpuAvg) { Write-Host ("  CPU Usage: {0}%" -f ([math]::Round($cpuAvg,2))) -ForegroundColor White; $somethingPrinted = $true }
            else { Write-Host "  CPU usage sample captured" -ForegroundColor White; $somethingPrinted = $true }
        }
        if ($mem) {
            $memMB = [int]$mem.CounterSamples[0].CookedValue
            Write-Host ("  Available MB: {0}" -f $memMB) -ForegroundColor White
            $somethingPrinted = $true
        }

        # Fallback: if counters aren't available, print guidance and a quick connectivity check
        if (-not $somethingPrinted) {
            Write-Host "  ⚠️  No performance counters returned. Try running PowerShell as Administrator and ensure the 'Performance Logs & Alerts' service is running." -ForegroundColor Yellow
            try {
                $gw4 = (Get-NetRoute -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Sort-Object RouteMetric | Select-Object -First 1).NextHop
                $gw6 = (Get-NetRoute -AddressFamily IPv6 -DestinationPrefix '::/0' -ErrorAction SilentlyContinue | Sort-Object RouteMetric | Select-Object -First 1).NextHop
                $gw = if ($gw4) { $gw4 } elseif ($gw6) { $gw6 } else { $null }
                if ($gw) {
                    $gwOk = Test-Connection -ComputerName $gw -Count 1 -Quiet -ErrorAction SilentlyContinue
                    $gwStatus = if ($gwOk) { '[OK]' } else { '[FAIL]' }
                    Write-Host ("  Default Gateway: {0} {1}" -f $gw, $gwStatus) -ForegroundColor White
                }
                try { Resolve-DnsName microsoft.com -ErrorAction Stop -Verbose:$false | Out-Null; Write-Host "  DNS microsoft.com: [OK]" -ForegroundColor White } catch { Write-Host "  DNS microsoft.com: [FAIL]" -ForegroundColor White }
            } catch { }
        }

        # Verbose diagnostics
    if ($VerbosePreference -eq 'Continue' -or ($PSBoundParameters.ContainsKey('Verbose'))) {
            Write-Host ""; Write-Host "Network Connectivity Tests:" -ForegroundColor Green
            $networkTests = @()
            $haveHpc = Import-HpcModule -Quiet
            if ($haveHpc) {
                try { $hpcNodes = Get-HpcNode -Scheduler $SchedulerNode -ErrorAction SilentlyContinue } catch { $hpcNodes = $null }
                if ($hpcNodes) {
                    $nodesToTest = $hpcNodes | Where-Object { $_.NetBiosName -and $_.NetBiosName -ne $env:COMPUTERNAME }
                    $maxTest = 50
                    $count = 0
                    foreach ($node in ($nodesToTest | Sort-Object NetBiosName)) {
                        $count++; if ($count -gt $maxTest) { break }
                        try {
                            $reachable = Test-Connection -ComputerName $node.NetBiosName -Count 2 -Quiet -ErrorAction SilentlyContinue
                            $latency = 'N/A'
                            if ($reachable) {
                                try {
                                    $ping = Test-Connection -ComputerName $node.NetBiosName -Count 1 -ErrorAction SilentlyContinue
                                    if ($ping) { $latency = ("{0}ms" -f ([int]$ping.ResponseTime)) }
                                } catch {}
                            } else { $latency = 'Failed' }
                            $ntype = 'Unknown'
                            if ($node.PSObject.Properties['NodeRole'] -and $node.NodeRole) {
                                if ($node.NodeRole -contains 'ComputeNode') { $ntype = 'Compute' }
                                elseif ($node.NodeRole -contains 'HeadNode') { $ntype = 'Head' }
                                elseif ($node.NodeRole -contains 'BrokerNode') { $ntype = 'Broker' }
                            } elseif ($node.PSObject.Properties['NodeType'] -and $node.NodeType) {
                                $ntype = [string]$node.NodeType
                            }
                            $networkTests += [pscustomobject]@{ Node=$node.NetBiosName; Reachable=$reachable; Latency=$latency; NodeType=$ntype }
                        } catch {
                            $networkTests += [pscustomobject]@{ Node=$node.NetBiosName; Reachable=$false; Latency='Error'; NodeType='Unknown' }
                        }
                    }
                }
            }
            if ($networkTests.Count -gt 0) {
                $netFormat = "   {0,-18} {1,-10} {2,-10} {3,-10}"
                Write-Host ($netFormat -f 'NODE','REACHABLE','LATENCY','TYPE') -ForegroundColor White
                Write-Host ("   " + ("-"*55)) -ForegroundColor White
                foreach ($t in ($networkTests | Sort-Object Node)) {
                    $rs = if ($t.Reachable) { 'Yes' } else { 'No' }
                    Write-Host ($netFormat -f $t.Node, $rs, $t.Latency, $t.NodeType) -ForegroundColor White
                }
            } else {
                Write-Host "   No network connectivity data available" -ForegroundColor Yellow
            }

            Write-Host ""; Write-Host "Performance Metrics:" -ForegroundColor Green
            try {
                $perfCounters = @{
                    'CPU Usage'          = (Get-Counter '\\Processor(_Total)\\% Processor Time' -SampleInterval 1 -MaxSamples 1 -ErrorAction SilentlyContinue)
                    'Memory Available'   = (Get-Counter '\\Memory\\Available MBytes' -SampleInterval 1 -MaxSamples 1 -ErrorAction SilentlyContinue)
                    'Network Utilization'= (Get-Counter '\\Network Interface(*)\\Bytes Total/sec' -SampleInterval 1 -MaxSamples 1 -ErrorAction SilentlyContinue)
                }
                if ($perfCounters['CPU Usage']) {
                    $cpuAvg2 = ($perfCounters['CPU Usage'].CounterSamples | Measure-Object -Property CookedValue -Average).Average
                    if ($null -ne $cpuAvg2) { Write-Host ("   CPU Usage............: {0}%" -f ([math]::Round($cpuAvg2,2))) -ForegroundColor White }
                }
                if ($perfCounters['Memory Available']) {
                    $memGB = [math]::Round(($perfCounters['Memory Available'].CounterSamples[0].CookedValue / 1024),2)
                    Write-Host ("   Available Memory.....: {0} GB" -f $memGB) -ForegroundColor White
                }
                if ($perfCounters['Network Utilization']) {
                    $totalBytes = ($perfCounters['Network Utilization'].CounterSamples | Measure-Object -Property CookedValue -Sum).Sum
                    if ($null -ne $totalBytes) {
                        $mbps = [math]::Round(($totalBytes / 1048576), 2)
                        Write-Host ("   Network Throughput...: {0} MB/s" -f $mbps) -ForegroundColor White
                    }
                }
            } catch { Write-Host "   Performance counters not available" -ForegroundColor Yellow }


            try {
                if ($haveHpc) {
                    Write-Host ""; Write-Host "HPC Specific Health Checks:" -ForegroundColor Green
                    # Database connectivity (best effort)
                    # Some environments don't support -Name param set; list and filter instead
                    $dbProps = Get-HpcClusterProperty -Scheduler $SchedulerNode -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '(?i)Database' }
                    if ($dbProps -and $dbProps.Count -gt 0) { Write-Host "   Database Connectivity: [OK] Property present" -ForegroundColor White }
                    else { Write-Host "   Database Connectivity: [WARN] Property not found" -ForegroundColor Yellow }
                } else { Write-Host "   Database Connectivity: [WARN] HPC module not available" -ForegroundColor Yellow }
            } catch { Write-Host ("   Database Connectivity: [ERROR] {0}" -f $_.Exception.Message) -ForegroundColor Yellow }

            # Certificate validity from registry thumbprint
            try {
                $thumb = $null
                try { $reg = Get-ItemProperty -Path 'HKLM:\\SOFTWARE\\Microsoft\\HPC' -ErrorAction SilentlyContinue; if ($reg -and $reg.SSLThumbprint) { $thumb = ($reg.SSLThumbprint -replace '\\s','').ToUpperInvariant() } } catch {}
                if ($thumb) {
                    $cert = Get-ChildItem -Path Cert:\\LocalMachine\\My -ErrorAction SilentlyContinue | Where-Object { ($_.Thumbprint -replace '\\s','').ToUpperInvariant() -eq $thumb } | Select-Object -First 1
                    if ($cert) {
                        $days = [int]([Math]::Floor(($cert.NotAfter - (Get-Date)).TotalDays))
                        if ($days -gt 30) { Write-Host ("   SSL Certificate.....: [OK] Valid for {0} days" -f $days) -ForegroundColor White }
                        elseif ($days -gt 0) { Write-Host ("   SSL Certificate.....: [WARN] Expires in {0} days" -f $days) -ForegroundColor Yellow }
                        else { Write-Host ("   SSL Certificate.....: [ERROR] Expired {0} days ago" -f ([math]::Abs($days))) -ForegroundColor Red }
                    } else { Write-Host "   SSL Certificate.....: [ERROR] Certificate not found" -ForegroundColor Red }
                } else { Write-Host "   SSL Certificate.....: [WARN] Thumbprint not available" -ForegroundColor Yellow }
            } catch { Write-Host "   SSL Certificate.....: [ERROR] Cannot verify certificate" -ForegroundColor Yellow }

            # Disk space on CCP_HOME
            try {
                $ccpHome = [Environment]::GetEnvironmentVariable('CCP_HOME','Machine')
                if ($ccpHome -and (Test-Path -LiteralPath $ccpHome)) {
                    $drive = [System.IO.Path]::GetPathRoot($ccpHome)
                    $disk = Get-CimInstance -ClassName Win32_LogicalDisk -ErrorAction SilentlyContinue | Where-Object { $_.DeviceID -eq $drive.TrimEnd('\\') }
                    if ($disk) {
                        $freeGB = [math]::Round(($disk.FreeSpace/1GB),2)
                        $pct = if ($disk.Size -gt 0) { [math]::Round((($disk.FreeSpace/$disk.Size)*100),1) } else { $null }
                        if ($null -ne $pct) {
                            if ($pct -gt 15) { Write-Host ("   HPC Drive Space.....: [OK] {0} GB free ({1}%)" -f $freeGB,$pct) -ForegroundColor White }
                            elseif ($pct -gt 5) { Write-Host ("   HPC Drive Space.....: [WARN] {0} GB free ({1}%)" -f $freeGB,$pct) -ForegroundColor Yellow }
                            else { Write-Host ("   HPC Drive Space.....: [ERROR] Low space: {0} GB free ({1}%)" -f $freeGB,$pct) -ForegroundColor Red }
                        }
                    }
                }
            } catch { Write-Host "   HPC Drive Space.....: [ERROR] Cannot check disk space" -ForegroundColor Yellow }

            Write-Host ""; Write-Host "MPI and High-Performance Networking:" -ForegroundColor Green
            # InfiniBand adapters
            try {
                $ibAdapters = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.InterfaceDescription -match '(?i)InfiniBand|Mellanox|RDMA' }
                if ($ibAdapters) {
                    $activeIb = $ibAdapters | Where-Object { $_.Status -eq 'Up' }
                    Write-Host ("   InfiniBand Adapters..: {0} total, {1} active" -f $ibAdapters.Count, $activeIb.Count) -ForegroundColor White
                    if ($activeIb.Count -gt 0) { Write-Host "   InfiniBand Check.....: [OK] Active adapters detected" -ForegroundColor White }
                    else { Write-Host "   InfiniBand Check.....: [ERROR] No active IB adapters" -ForegroundColor Red }
                } else {
                    Write-Host "   InfiniBand Adapters..: 0 total, 0 active" -ForegroundColor White
                    Write-Host "   InfiniBand Check.....: [INFO] None detected" -ForegroundColor Yellow
                }
            } catch { Write-Host "   InfiniBand Check.....: [ERROR] Cannot check IB adapters" -ForegroundColor Yellow }

            # MPI installation
            try {
                $mpiInstalled = $false; $mpiVersion = 'Unknown'
                try { $msmpi = Get-ItemProperty -Path 'HKLM:\\SOFTWARE\\Microsoft\\MPI' -ErrorAction SilentlyContinue } catch { $msmpi = $null }
                if ($msmpi) { $mpiInstalled = $true; $mpiVersion = 'Microsoft MPI'; if ($msmpi.Version) { $mpiVersion += (" v{0}" -f $msmpi.Version) } }
                if ($mpiInstalled) {
                    Write-Host ("   MPI Installation.....: [OK] {0}" -f $mpiVersion) -ForegroundColor White
                    try { $mpiexec = Get-Command mpiexec -ErrorAction SilentlyContinue; if ($mpiexec) { Write-Host "   MPI Executable.......: [OK] mpiexec found in PATH" -ForegroundColor White } else { Write-Host "   MPI Executable.......: [WARN] mpiexec not in PATH" -ForegroundColor Yellow } } catch { Write-Host "   MPI Executable.......: [WARN] Cannot verify mpiexec" -ForegroundColor Yellow }
                } else {
                    Write-Host "   MPI Installation.....: [WARN] No MPI runtime detected" -ForegroundColor Yellow
                }
            } catch { Write-Host "   MPI Installation.....: [ERROR] Cannot check MPI installation" -ForegroundColor Yellow }

            # RDMA/NetworkDirect services
            try {
                $rdmaServices = Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match '(?i)RDMA|NetworkDirect' }
                if ($rdmaServices) {
                    $running = $rdmaServices | Where-Object { $_.Status -eq 'Running' }
                    Write-Host ("   RDMA Services........: {0} total, {1} running" -f $rdmaServices.Count, $running.Count) -ForegroundColor White
                    if ($running.Count -gt 0) { Write-Host "   RDMA Status..........: [OK] RDMA services active" -ForegroundColor White }
                    else { Write-Host "   RDMA Status..........: [WARN] No RDMA services running" -ForegroundColor Yellow }
                } else {
                    Write-Host "   RDMA Services........: None found" -ForegroundColor White
                    Write-Host "   RDMA Status..........: [INFO] Standard TCP/IP networking" -ForegroundColor Yellow
                }
            } catch { Write-Host "   RDMA Check...........: [ERROR] Cannot check RDMA services" -ForegroundColor Yellow }

            # Recommendations
            Write-Host ""; Write-Section "COMPREHENSIVE HEALTH ANALYSIS & RECOMMENDATIONS" 'Cyan'
            $issues = @(); $warnings = @()
            try {
                $unreachList = @($networkTests | Where-Object { -not $_.Reachable })
                $unreachCount = $unreachList.Count
                if ($unreachCount -gt 0) { $issues += ("{0} node(s) are not reachable via network" -f $unreachCount) }
            } catch {}
            try {
                if ($cpuAvg2 -and $cpuAvg2 -gt 90) { $warnings += ("High CPU usage detected: {0}%" -f ([math]::Round($cpuAvg2,2))) }
            } catch {}
            try {
                if ($perfCounters['Memory Available']) {
                    $memGB2 = [math]::Round(($perfCounters['Memory Available'].CounterSamples[0].CookedValue / 1024),2)
                    if ($memGB2 -lt 2) { $warnings += ("Low available memory: {0} GB" -f $memGB2) }
                }
            } catch {}

            if (($issues.Count + $warnings.Count) -eq 0) {
                Write-Host "[EXCELLENT] No issues or warnings detected - Cluster is in optimal health!" -ForegroundColor Green
            } else {
                if ($issues.Count -gt 0) {
                    Write-Host "[CRITICAL] Issues detected that require immediate attention:" -ForegroundColor Red
                    for ($i=0; $i -lt $issues.Count; $i++) {
                        Write-Host ("   CRITICAL {0}: {1}" -f ($i+1), $issues[$i]) -ForegroundColor Red
                        if ($issues[$i] -like '*not reachable*' -and $unreachList) {
                            Write-Host ("   ACTION    : Investigate network issues with: {0}" -f (($unreachList | Select-Object -ExpandProperty Node) -join ', ')) -ForegroundColor Yellow
                        }
                    }
                    Write-Host ""
                }
                if ($warnings.Count -gt 0) {
                    Write-Host "[WARNING] Warnings that should be monitored:" -ForegroundColor Yellow
                    for ($i=0; $i -lt $warnings.Count; $i++) {
                        $w = $warnings[$i]
                        Write-Host ("   WARNING {0}: {1}" -f ($i+1), $w) -ForegroundColor Yellow
                        if ($w -like '*CPU*') { Write-Host "   SUGGEST : Monitor CPU usage and consider load balancing" -ForegroundColor White }
                        elseif ($w -like '*memory*') { Write-Host "   SUGGEST : Monitor memory usage and consider adding more RAM" -ForegroundColor White }
                    }
                    Write-Host ""
                }
                Write-Host "Next Steps:" -ForegroundColor Green
                Write-Host "   1. Address critical issues immediately" -ForegroundColor White
                Write-Host "   2. Plan remediation for warnings during next maintenance window" -ForegroundColor White
                Write-Host "   3. Re-run this validation after making changes" -ForegroundColor White
                Write-Host "   4. Consider implementing automated monitoring" -ForegroundColor White
            }
        }
    } catch {
        Write-Host "  ⚠️  Health counters not available" -ForegroundColor Yellow
    }
}

function Get-InsightRunModes {
    @(
    @{ Name='All';            Source='Internal Suite'; Description='Run the full internal diagnostics suite' }
    @{ Name='ListModules';    Source='Internal'; Description='List all implemented run modes' }
    @{ Name='NetworkFix';     Source='Internal'; Description='Network analysis and optional auto-repair' }
    @{ Name='PortTest';       Source='Internal'; Description='Test TCP port reachability (single or range)' }
    @{ Name='CommandTest';    Source='Internal'; Description='HPC command/module validation' }
    @{ Name='NodeValidation'; Source='Internal'; Description='Comprehensive node and cluster health validation' }
    @{ Name='NodeConfig';     Source='Internal'; Description='Node configuration and HPC registry validation' }
    @{ Name='ClusterMetadata';Source='Internal'; Description='Cluster overview and properties' }
    @{ Name='NodeTemplates';  Source='Internal'; Description='Node templates and groups' }
    @{ Name='JobHistory';     Source='Internal'; Description='Job queue and history analysis' }
    @{ Name='JobDetails';     Source='Internal'; Description='Print details for a specific job (Get-HpcJobDetails)' }
    @{ Name='NodeHistory';    Source='Internal'; Description='Show node state history for a node' }
    @{ Name='ClusterMetrics'; Source='Internal'; Description='Performance metrics and monitoring' }
    @{ Name='MetricValueHistory'; Source='Internal'; Description='Export historical metric values between dates' }
    @{ Name='ClusterTopology';Source='Internal'; Description='Node topology and network reachability' }
    @{ Name='ServicesStatus'; Source='Internal'; Description='HPC services status' }
    @{ Name='DiagnosticTests';Source='Internal'; Description='Built-in diagnostic tests (certtest)' }
    @{ Name='CommunicationTest'; Source='Internal'; Description='Compute node certificate discovery and headnode API test' }
    @{ Name='SQLTrace';       Source='Internal'; Description='Extract SQL instance from registry and suggest detailed XE collector/analyzer' }
    @{ Name='SystemInfo';     Source='Internal'; Description='System information/specs' }
    @{ Name='AdvancedHealth'; Source='Internal'; Description='Advanced health checks and recommendations' }
    )
}

# Windows (compute node) HPCPackCommunication test
function Invoke-CommunicationTest {
    if ($Script:CliTipsOnly) {
        Write-CliHeader -Name 'Communication - Certificate Test'
        Write-CliTips @(
            '# Discover HPCPackCommunication certificate on Windows',
            'Get-ChildItem Cert:\\LocalMachine\\My | Where-Object { $_.Subject -like "*HPCPackCommunication*" -and $_.NotAfter -gt (Get-Date) } | Select-Object -First 1',
            '# Fallback (visibility only): search Trusted Root if not present in My store',
            'Get-ChildItem Cert:\\LocalMachine\\Root | Where-Object { $_.Subject -like "*HPCPackCommunication*" -and $_.NotAfter -gt (Get-Date) } | Select-Object -First 1'
        )
        Write-CliHeader -Name 'COMMUNICATION CERT & ENDPOINT TEST'
        Write-Host "Windows (compute node) compare serial and thumbprint" -ForegroundColor Green
        Write-Host " "
        Write-CliTips @(
    '#    Discover HPCPackCommunication Certificate',
   '# Load certificate by thumbprint',
    'Write-Host "`n🔍 Searching for HPCPackCommunication certificate..." -ForegroundColor Cyan',
    '$cert = Get-ChildItem Cert:\LocalMachine\My | Where-Object {',
    '    $_.Subject -like "*HPCPackCommunication*" -and $_.NotAfter -gt (Get-Date)',
    '} | Select-Object -First 1',
    'if (-not $cert) {',
    '    Write-Host "🔎 Not found in LocalMachine\My; checking LocalMachine\Root (visibility only)..." -ForegroundColor DarkYellow',
    '    $cert = Get-ChildItem Cert:\LocalMachine\Root | Where-Object {',
    '        $_.Subject -like "*HPCPackCommunication*" -and $_.NotAfter -gt (Get-Date)',
    '    } | Select-Object -First 1',
    '}',
    'if (-not $cert) {',
    '    Write-Warning "❌ Certificate not found or expired in My or Root."',
    '    return',
    '}',
    'Write-Host "`n✅ Found a Local HPCPackCommunication certificate:" -ForegroundColor Green',
    '$cert = Get-ChildItem -Path Cert:\LocalMachine\My | Where-Object { $_.Thumbprint -eq $thumbprint }',
    'if (-not $cert) { Write-Error "❌ Certificate with thumbprint $thumbprint not found."; return }',
    'Write-Host "`n✅ Certificate loaded:" -ForegroundColor Green',
    '$cert | Format-List Subject, Thumbprint, HasPrivateKey, NotAfter',
    'if (-not $cert.HasPrivateKey) { Write-Error "❌ Certificate does not have a private key. Cannot use for client authentication."; return }',
    '',
    '# Enforce TLS 1.2',
    '[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12',
    '',
    '# Safe SSL override using .NET delegate (avoids runspace errors)',
    'if (-not ("SSLBypass" -as [type])) {',
    '    Add-Type @"',
    '    using System;',
    '    using System.Net;',
    '    using System.Net.Security;',
    '    using System.Security.Cryptography.X509Certificates;',
    '    public static class SSLBypass {',
    '        public static void Enable() {',
    '            ServicePointManager.ServerCertificateValidationCallback =',
    '                new RemoteCertificateValidationCallback(',
    '                    delegate (object sender, X509Certificate cert, X509Chain chain, SslPolicyErrors sslPolicyErrors) {',
    '                        return true;',
    '                    }',
    '                );',
    '        }',
    '        public static void Reset() {',
    '            ServicePointManager.ServerCertificateValidationCallback = null;',
    '        }',
    '    }',
    '"@',
    '}',
    '',
    '# Enable SSL bypass (for testing only)',
    '[SSLBypass]::Enable()',
    '',
    '#    Resolve headnode name',
    '$hn = $env:CCP_SCHEDULER; if (-not $hn -or -not $hn.Trim()) { $hn = "headnode" }  # set your headnode here if env var is unset',
    '#    Optional quick reachability checks',
    'Test-Connection $hn -Count 1',
    'Test-NetConnection -ComputerName $hn -Port 443 -InformationLevel Detailed',
    '',
    '# Define target URI',
    '$ub = [System.UriBuilder]::new(''https'',$hn,443,''/HpcNaming/api/fabric/resolve/singleton/MonitoringStatefulService'')',
    '$uri = $ub.Uri.AbsoluteUri',
    'Write-Host "`n🌐 Testing endpoint: $uri" -ForegroundColor Cyan',
    '',
    '# Make the request',
    'try {',
    '    $response = Invoke-WebRequest -Uri $uri -Certificate $cert -UseBasicParsing',
    '    Write-Host "✅ Request succeeded. Status code: $($response.StatusCode)" -ForegroundColor Green',
    '    $response.Content',
    '} catch {',
    '    Write-Error "❌ Request failed: $($_.Exception.Message)"',
    '    if ($_.Exception.InnerException) {',
    '        Write-Host "🔎 Inner Exception: $($_.Exception.InnerException.Message)" -ForegroundColor DarkYellow',
    '    }',
    '} finally {',
    '    # Reset SSL override',
    '    [SSLBypass]::Reset()',
    '}'
    )
        Write-Host "Linux (compute node) - compare serial and thumbprint" -ForegroundColor Green
        Write-Host " "
        Write-CliTips @(
    '#    tail LinuxNodeAgent log for cert activity',
    'tail -f /var/log/azure/Microsoft.HpcPack.LinuxNodeAgent2016U1/extension.log',
    '#    show nodemanager certificate details + fingerprint',
    'openssl x509 -in /opt/hpcnodemanager/certs/nodemanager.crt -noout -text -fingerprint -sha1',
    '#    test headnode endpoint with node cert/key',
    'curl -vk https://HEADNODE:443/HpcNaming/api/fabric/resolve/singleton/MonitoringStatefulService --cert /opt/hpcnodemanager/certs/nodemanager.crt --key /opt/hpcnodemanager/certs/nodemanager.key'
    )
        return
    }

    # Emit CLI tips variant when requested


    if ($Script:CliTipsOnly) { return }

    try {
    # Windows (compute node) Discover HPCPackCommunication Certificate (or honor overrides)
        Write-Host "`n🔍 Searching for HPCPackCommunication certificate..." -ForegroundColor Cyan

        $cert = $null
    # 1) Explicit PFX provided
    if ($ClientCertPfxPath) {
            try {
                $pfxPwd = $null
                if ($ClientCertPfxPassword) { $pfxPwd = $ClientCertPfxPassword }
                $cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($ClientCertPfxPath, $pfxPwd, 'Exportable,MachineKeySet')
                Write-Host "✅ Loaded client certificate from PFX path." -ForegroundColor Green
            } catch {
                Write-Warning ("❌ Failed to load PFX '{0}': {1}" -f $ClientCertPfxPath, $_.Exception.Message)
            }
        }
    # 2) Thumbprint provided (strict: require in LocalMachine\My and with private key)
    if (-not $cert -and $ClientCertThumbprint) {
            $tp = ($ClientCertThumbprint -replace '\s','').ToUpperInvariant()
            try {
        $cert = Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Thumbprint -eq $tp -and $_.NotAfter -gt (Get-Date) } | Select-Object -First 1
        } catch { Write-Warning ("❌ Error searching for thumbprint in My: {0}" -f $_.Exception.Message) }
        if (-not $cert) { Write-Error ("❌ Certificate with thumbprint {0} not found in LocalMachine\\My." -f $tp); return }
        if (-not $cert.HasPrivateKey) { Write-Error ("❌ Certificate {0} does not have a private key. Cannot use for client authentication." -f $tp); return }
        Write-Host "✅ Using client certificate from LocalMachine\\My by thumbprint." -ForegroundColor Green
        }
        # 3) Auto-discover by subject when no override provided
        if (-not $cert) {
            $cert = Get-ChildItem Cert:\LocalMachine\My | Where-Object {
                $_.Subject -like "*HPCPackCommunication*" -and $_.NotAfter -gt (Get-Date)
            } | Select-Object -First 1

            if (-not $cert) {
                Write-Host "🔎 Not found in LocalMachine\\My; checking Trusted Root (visibility only)..." -ForegroundColor DarkYellow
                $cert = Get-ChildItem Cert:\LocalMachine\Root | Where-Object {
                    $_.Subject -like "*HPCPackCommunication*" -and $_.NotAfter -gt (Get-Date)
                } | Select-Object -First 1
            }
        }

        if (-not $cert) {
            Write-Warning "❌ Certificate not found or expired in My or Root."
            return
        }

        if ($cert.HasPrivateKey) {
            Write-Host "`n✅ Using client certificate (private key present):" -ForegroundColor Green
        } else {
            Write-Host "`n⚠️  Certificate present but private key missing; proceeding without client certificate." -ForegroundColor Yellow
        }
        $cert | Format-List Subject, Thumbprint, NotAfter, HasPrivateKey


    # Prefer TLS 1.2; allow fallback to TLS 1.1/1.0 if the server is older
    $proto = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls
    [Net.ServicePointManager]::SecurityProtocol = $proto
        # endregion

    # Override SSL Validation (Safe for PowerShell 5.1) using a static helper class to avoid runspace issues
    Write-Host "`n⚠️ Overriding SSL validation for testing..." -ForegroundColor Yellow
    if (-not ('SSLBypass' -as [type])) {
        Add-Type @"
    using System;
    using System.Net;
    using System.Net.Security;
    using System.Security.Cryptography.X509Certificates;
    public static class SSLBypass {
        public static void Enable() {
            ServicePointManager.ServerCertificateValidationCallback =
                new RemoteCertificateValidationCallback(
                    delegate (object sender, X509Certificate cert, X509Chain chain, SslPolicyErrors sslPolicyErrors) {
                        return true;
                    }
                );
        }
        public static void Reset() {
            ServicePointManager.ServerCertificateValidationCallback = null;
        }
    }
"@
    }
    [SSLBypass]::Enable()


    # Define Target URI using the provided SchedulerNode or local machine as fallback (hardened)
    $hn = if ($SchedulerNode -and -not [string]::IsNullOrWhiteSpace($SchedulerNode)) { $SchedulerNode } elseif ($env:CCP_SCHEDULER) { $env:CCP_SCHEDULER } else { $env:COMPUTERNAME }
    $hn = ($hn | ForEach-Object { $_.ToString() }).Trim()
    if ([string]::IsNullOrWhiteSpace($hn)) {
        Write-Error "Headnode name could not be resolved. Provide -SchedulerNode or set CCP_SCHEDULER."
        return
    }
    Write-Host ("Resolved headnode: {0}" -f $hn) -ForegroundColor DarkGray

    # Optional quick reachability checks (shown only with -Verbose)
    if ($VerbosePreference -eq 'Continue') {
        Write-Verbose "Running quick reachability checks..."
        try {
            Test-Connection -ComputerName $hn -Count 1 | Out-Host
        } catch {
            Write-Verbose ("Test-Connection failed: {0}" -f $_.Exception.Message)
        }
        try {
            Test-NetConnection -ComputerName $hn -Port 443 -InformationLevel Detailed | Out-Host
        } catch {
            Write-Verbose ("Test-NetConnection failed: {0}" -f $_.Exception.Message)
        }
    }
    try {
        $ub = [System.UriBuilder]::new('https',$hn,443,'/HpcNaming/api/fabric/resolve/singleton/MonitoringStatefulService')
        $uri = $ub.Uri.AbsoluteUri
    } catch {
        Write-Error ("Failed to build URI for headnode '{0}': {1}" -f $hn, $_.Exception.Message)
        return
    }
    Write-Host "`n🌐 Testing endpoint: $uri" -ForegroundColor Cyan
    Write-Host "   Tip: If TLS fails, try the scheduler FQDN and ensure it's in the certificate SAN: e.g., headnode.contoso.local" -ForegroundColor DarkGray
        # endregion

        # Invoke Request
        try {
            # Only use a client certificate if it has a private key (i.e., from LocalMachine\My)
            $certToUse = $null
            if ($cert -and $cert.HasPrivateKey) { $certToUse = $cert } else { Write-Host "⚠️  Found certificate without private key (likely from Trusted Root). Proceeding without client certificate." -ForegroundColor Yellow }
            if ($certToUse) {
                $response = Invoke-WebRequest -Uri $uri -Certificate $certToUse -UseBasicParsing
            } else {
                $response = Invoke-WebRequest -Uri $uri -UseBasicParsing
            }
            Write-Host "✅ Request succeeded. Status code: $($response.StatusCode)" -ForegroundColor Green
            $response.Content
        } catch {
            Write-Error "❌ Request failed: $($_.Exception.Message)"
            if ($_.Exception.InnerException) {
                Write-Host "🔎 Inner Exception: $($_.Exception.InnerException.Message)" -ForegroundColor DarkYellow
                if ($_.Exception.InnerException.Message -match 'handshake|client certificate|authentication') {
                    Write-Host "💡 Likely mutual TLS required by headnode. Run from a compute node that has the HPCPackCommunication client cert, or provide -ClientCertThumbprint or -ClientCertPfxPath." -ForegroundColor Yellow
                }
            }
        } finally {
            # Reset callback after testing
            [SSLBypass]::Reset()
        }
    } catch {
        Write-Error $_
    }
}
function Invoke-JobDetails {
    param([int]$JobId)
    if ($Script:CliTipsOnly) {
    Write-CliHeader -Name 'Job Details'
        Write-CliTips @(
            '# Print details for a specific job using HPC Pack cmdlet',
            'Get-HpcJobDetails -JobId <N>',
            '# Example:',
            'Get-HpcJobDetails -JobId 12345',
            '# Get job object',
            'Get-HpcJob -Id <JobId> -Scheduler <SchedulerNode>',
            '# List tasks for the job (table)',
            'Get-HpcTask -JobId <JobId> -Scheduler <SchedulerNode> | Format-Table Id,Name,State,ExitCode -Auto'
        )
        return
    }
    if (-not $JobId) { return }
    Write-Section ("JOB DETAILS #{0}" -f $JobId)
    try {
        $info = Get-HpcJobDetails -JobId $JobId
        if (-not $info) { Write-Host "  ⚠️  No details returned for JobId $JobId" -ForegroundColor Yellow; return }
        Write-Host ("  Job: #{0} '{1}'" -f $info.JobId, $info.Name) -ForegroundColor White
        Write-Host ("  Owner.............: {0}" -f $info.Owner) -ForegroundColor White
        Write-Host ("  State.............: {0}" -f $info.State) -ForegroundColor White
        if ($info.SubmitTime) { Write-Host ("  Submitted.........: {0}" -f $info.SubmitTime) -ForegroundColor White }
        if ($info.StartTime)  { Write-Host ("  Started...........: {0}" -f $info.StartTime) -ForegroundColor White }
        if ($info.EndTime)    { Write-Host ("  Ended.............: {0}" -f $info.EndTime) -ForegroundColor White }
        Write-Host ("  Nodes Allocated...: {0}" -f $info.NodeCount) -ForegroundColor White
        Write-Host ("  Tasks.............: {0}" -f $info.TaskCount) -ForegroundColor White
        $tasksToShow = @()
        if ($info.Tasks) { $tasksToShow = @($info.Tasks) }
        if ($tasksToShow.Count -gt 0) {
            Write-Host ""; Write-Host "  Tasks:" -ForegroundColor Green
            $fmt = "  {0,-6} {1,-18} {2,-10} {3,-40} {4}"
            Write-Host ($fmt -f 'ID','STATE','EXITCODE','COMMAND','ERROR') -ForegroundColor White
            Write-Host ("  " + ("-"*120)) -ForegroundColor White
            foreach ($t in $tasksToShow) {
                $cmd = [string]$t.CommandLine
                if ($cmd.Length -gt 40) { $cmd = $cmd.Substring(0,37) + '...' }
                $exit = if ($null -ne $t.ExitCode) { $t.ExitCode } else { '' }
                $err = ''
                if ($t.PSObject.Properties['ErrorMessage'] -and $t.ErrorMessage) { $err = [string]$t.ErrorMessage }
                if ($err.Length -gt 60) { $err = $err.Substring(0,57) + '...' }
                Write-Host ($fmt -f $t.Id, $t.State, $exit, $cmd, $err) -ForegroundColor White
            }
        }

        # Verbose tips: how to get more details via HPC CLI
        if ($VerbosePreference -eq 'Continue') {
            Write-Host ""; Write-Host "  Tips for more details (HPC CLI):" -ForegroundColor Green
            $schedArg = if ($PSBoundParameters.ContainsKey('SchedulerNode') -and $SchedulerNode) { "/scheduler:$SchedulerNode" } else { $null }
            $cmd1 = @('job','view',"$JobId")
            if ($schedArg) { $cmd1 += $schedArg }
            $cmd2 = @('job','view',"$JobId")
            if ($schedArg) { $cmd2 += $schedArg }
            $cmd2 += '/detailed:true'
            Write-Host ("    > {0}" -f ($cmd1 -join ' ')) -ForegroundColor Gray
            Write-Host ("    > {0}" -f ($cmd2 -join ' ')) -ForegroundColor Gray
        }

    } catch {
        Write-Host ("  ⚠️  Error printing job details: {0}" -f $_.Exception.Message) -ForegroundColor Yellow
    }
}

function Get-HpcNodeHistory {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][string]$NodeName,
        [int]$DaysBack = 7
    )

    if (-not (Import-HpcModule -Quiet)) {
        Write-Warning "❌ HPC module not available; cannot query node history."
        return $null
    }

    $start = (Get-Date).AddDays(-[int]$DaysBack)
    $end = Get-Date
    try {
        return Get-HpcNodeStateHistory -StartDate $start -EndDate $end -Name $NodeName -Scheduler $SchedulerNode -ErrorAction SilentlyContinue
    } catch {
        Write-Warning ("❌ Could not retrieve node history for {0}: {1}" -f $NodeName, $_.Exception.Message)
        return $null
    }
}

function Invoke-NodeHistory {
    param([string]$NodeName,[int]$DaysBack = 7)
    if ($Script:CliTipsOnly) {
    Write-CliHeader -Name 'Node History'
        Write-CliTips @(
            '# Node state history',
            'Get-HpcNodeHistory -Scheduler <SchedulerNode> -NodeName <NodeName> -DaysBack <DaysBack>'
        )
        return
    }
    if (-not $NodeName) { return }
    Write-Section ("NODE HISTORY: {0} (Last {1} days)" -f $NodeName, $DaysBack)
    try {
        $hist = Get-HpcNodeHistory -NodeName $NodeName -DaysBack $DaysBack
        $rows = @($hist)
        if (-not $rows -or $rows.Count -eq 0) { Write-Host "  ⚠️  No history found" -ForegroundColor Yellow; return }

        $fmt = "  {0,-22} {1,-14} {2}"
        Write-Host ($fmt -f 'TIMESTAMP','EVENT','NODE') -ForegroundColor White
        Write-Host ("  " + ("-"*80)) -ForegroundColor White
        foreach ($e in $rows) {
            $ts = $null
            if ($e.PSObject.Properties['EventTime']) { $ts = $e.EventTime }
            elseif ($e.PSObject.Properties['Timestamp']) { $ts = $e.Timestamp }
            elseif ($e.PSObject.Properties['TimeStamp']) { $ts = $e.TimeStamp }
            $evt = if ($e.PSObject.Properties['Event']) { [string]$e.Event } elseif ($e.PSObject.Properties['State']) { [string]$e.State } else { '' }
            $node = if ($e.PSObject.Properties['NodeName']) { [string]$e.NodeName } elseif ($e.PSObject.Properties['Name']) { [string]$e.Name } else { '' }
            Write-Host ($fmt -f $ts, $evt, $node) -ForegroundColor White
        }
    } catch {
        Write-Host ("  ⚠️  Error printing node history: {0}" -f $_.Exception.Message) -ForegroundColor Yellow
    }
}

# Standalone port test run mode
function Invoke-PortTest {
    if ($Script:CliTipsOnly) {
        Write-CliHeader -Name 'Port Test'
        Write-CliTips @(
            "# Test a single port on a node",
            "Test-NetConnection -ComputerName <NodeName> -Port <Port> -InformationLevel Detailed",
            "# Test a range of ports",
            '$ports = @(40000..40003); foreach ($p in $ports) { Test-NetConnection -ComputerName <NodeName> -Port $p }'
        )
        return
    }
    Write-Section "PORT REACHABILITY TEST"
    $targetNode = if ($NodeName) { $NodeName } else { $SchedulerNode }
    $portList = if ($Port) { @($Port) }
               elseif ($Ports) { $Ports }
               else { @(80,443,5800,5801,5802,5969,5970,9087,9090,9091,9094) }
    Write-Host ("  Target Node: {0}" -f $targetNode) -ForegroundColor White
    Write-Host ("  Ports......: {0}" -f ($portList -join ', ')) -ForegroundColor White
    Test-HpcNodePorts -NodeName $targetNode -Ports $portList
    if ($VerbosePreference -eq 'Continue') {
        Write-Host ""
        Write-Host "CLI tips (PowerShell):  PORT REACHABILITY TEST" -ForegroundColor Cyan
        Write-CliTips @(
            "# Test a single port on a node",
            "Test-NetConnection -ComputerName <NodeName> -Port <Port> -InformationLevel Detailed",
            "# Test a range of ports",
            "$ports = @(40000..40003); foreach ($p in $ports) { Test-NetConnection -ComputerName <NodeName> -Port $p }"
        )
    }
}

function Show-InsightHelp {
    Write-Header 'HPC COMPREHENSIVE DIAGNOSTICS AND TROUBLESHOOTING TOOL'
    Write-Host "Usage:" -ForegroundColor Green
    Write-Host "  .\\$Script:SelfName -RunMode <Mode> -SchedulerNode <headnode> [options]" -ForegroundColor White
    Write-Host "  .\\$Script:SelfName <Mode> [<headnode>] [options]" -ForegroundColor White
    Write-Host ""
    Write-Host "RunModes:" -ForegroundColor Green
    foreach ($m in Get-InsightRunModes) {
        Write-Host ("  {0,-16} {1}" -f $m.Name, $m.Description) -ForegroundColor White
    }
    Write-Host ""
    Write-Host "Options:" -ForegroundColor Green
    Write-Host "  -FixNetworkIssues     (Diagnostics only)" -ForegroundColor White
    Write-Host "  -EnableMpiTesting     (Diagnostics only)" -ForegroundColor White
    Write-Host "                         When used alone: runs a quick mpiexec -n 1 hostname smoke test" -ForegroundColor DarkGray
    Write-Host "                         When combined with a RunMode: runs the smoke test after the mode" -ForegroundColor DarkGray
    Write-Host "  -TimeoutSeconds N     (Diagnostics only, default 120)" -ForegroundColor White
    Write-Host "  -TestHpcNodePorts     With NetworkFix, test TCP ports on a node" -ForegroundColor White
    Write-Host "  -Ports <int[]>        Port list or range (e.g., @(40000..40003)) for -TestHpcNodePorts" -ForegroundColor White
    Write-Host "  -Port <int>           Single port for -TestHpcNodePorts (preferred over -Ports if provided)" -ForegroundColor White
    Write-Host "  -JobId N              Print details for JobId N (uses Get-HpcJobDetails)" -ForegroundColor White
    Write-Host "  -NodeName <name>      With RunMode JobHistory, show node state history for this node" -ForegroundColor White
    Write-Host "  -DaysBack N           Days back for node history (default 7)" -ForegroundColor White
    Write-Host "  -ExportToFile         Export console output to a log file" -ForegroundColor White
    Write-Host "  -ReportFile <path>    Specify log file path (default: report.log)" -ForegroundColor White
    Write-Host "  -MetricStartDate <dt> Optional start date for MetricValueHistory (default: now-7d)" -ForegroundColor White
    Write-Host "  -MetricEndDate <dt>   Optional end date for MetricValueHistory (default: now)" -ForegroundColor White
    Write-Host "  -MetricOutputPath <p> Optional CSV output path for MetricValueHistory (default: MetricValueHistory.csv)" -ForegroundColor White
    Write-Host "  -ShowHelp | -h | -help | --help | -?   Show this help" -ForegroundColor White
    Write-Host "  -DeepHelp                                   Show additional internal details" -ForegroundColor White
    Write-Host "  -CliTips                 Print only CLI tips for the selected RunMode(s)" -ForegroundColor White
    Write-Host ""
    Write-Host "Examples:" -ForegroundColor Green
    Write-Host "  .\\$Script:SelfName -RunMode All -Verbose" -ForegroundColor Cyan
    Write-Host "  .\\$Script:SelfName -RunMode All -SchedulerNode headnode" -ForegroundColor White
    Write-Host "  .\\$Script:SelfName -RunMode ClusterTopology -SchedulerNode headnode" -ForegroundColor White
    Write-Host "  .\\$Script:SelfName -RunMode NetworkFix -FixNetworkIssues -SchedulerNode headnode" -ForegroundColor White
    Write-Host "  .\\$Script:SelfName -JobId 12345 -SchedulerNode headnode" -ForegroundColor White
    Write-Host "  .\\$Script:SelfName JobHistory -JobId 12345 -Verbose" -ForegroundColor White
    Write-Host "  .\\$Script:SelfName JobHistory -NodeName IaaSCN000 -DaysBack 14" -ForegroundColor White
    Write-Host "  .\\$Script:SelfName NodeHistory headnode -DaysBack 14" -ForegroundColor White
    Write-Host "  .\\$Script:SelfName All -Verbose -ExportToFile -ReportFile report.log" -ForegroundColor White
    Write-Host "  .\\$Script:SelfName All -Verbose" -ForegroundColor Cyan
    Write-Host "  .\\$Script:SelfName ClusterTopology" -ForegroundColor White
    Write-Host "  .\\$Script:SelfName ClusterTopology headnode" -ForegroundColor White
    Write-Host "  .\\$Script:SelfName AdvancedHealth -Verbose" -ForegroundColor White
    Write-Host "  .\\$Script:SelfName ServicesStatus -CliTips   # tips for services only" -ForegroundColor White
    Write-Host "  .\\$Script:SelfName SystemInfo -CliTips       # tips for system info only" -ForegroundColor White
    Write-Host "  .\\$Script:SelfName ListModules                # list all run modes" -ForegroundColor White
    Write-Host "  .\\$Script:SelfName ClusterMetadata -CliTips   # print tips only" -ForegroundColor White
    Write-Host "  .\\$Script:SelfName ServicesStatus -CliTips   # tips for services only" -ForegroundColor White
    Write-Host "  .\\$Script:SelfName SystemInfo -CliTips       # tips for system info only" -ForegroundColor White
    Write-Host "  .\\$Script:SelfName ListModules                # list all run modes" -ForegroundColor White
    Write-Host "  .\\$Script:SelfName CommunicationTest -SchedulerNode headnode" -ForegroundColor White
    Write-Host "  .\\$Script:SelfName CommunicationTest -Verbose" -ForegroundColor White
    Write-Host "  .\\$Script:SelfName CommunicationTest -CliTips   # print just the commands" -ForegroundColor White
    Write-Host "  .\\$Script:SelfName CommunicationTest -SchedulerNode headnode -ClientCertThumbprint <THUMBPRINT>" -ForegroundColor White
    Write-Host "  .\\$Script:SelfName CommunicationTest -SchedulerNode headnode -ClientCertPfxPath C:\\path\\nodecert.pfx -ClientCertPfxPassword (Read-Host -AsSecureString)" -ForegroundColor White
    Write-Host "  .\\$Script:SelfName MetricValueHistory -Verbose   # export last 7 days to MetricValueHistory.csv" -ForegroundColor White
    Write-Host "  .\\$Script:SelfName MetricValueHistory -MetricStartDate '2025-08-01' -MetricEndDate '2025-08-14' -MetricOutputPath C:\\temp\\mvh.csv" -ForegroundColor White
    Write-Host "  .\\$Script:SelfName NetworkFix -TestHpcNodePorts -NodeName IaaSCN104 -Port 40000" -ForegroundColor White
    Write-Host "  .\\$Script:SelfName NetworkFix -TestHpcNodePorts -NodeName IaaSCN104 -Ports @(40000..40003)" -ForegroundColor White
    Write-Host "" 
    Write-Host "Reference: Microsoft HPC Pack PowerShell, Log files, Trubleshooting, and  Diagnostics references" -ForegroundColor Gray
    Write-Host "           https://learn.microsoft.com/en-us/powershell/high-performance-computing/microsoft-hpc-pack-command-reference?view=hpc19-ps" -ForegroundColor Gray
    Write-Host "           https://learn.microsoft.com/en-us/powershell/high-performance-computing/using-service-log-files-for-hpc-pack?view=hpc19-ps" -ForegroundColor Gray
    Write-Host "           https://learn.microsoft.com/en-us/troubleshoot/azure/hpc/pack/welcome-hpc-pack" -ForegroundColor Gray
    Write-Host "           https://learn.microsoft.com/en-us/powershell/high-performance-computing/diagnostics-hpc-cluster-manager?view=hpc19-ps" -ForegroundColor Gray
}

function Show-DeepHelp {
    Write-Host ""; Write-Header 'ADDITIONAL DETAILS'
    Write-Section "How it works" 'Cyan'
    Write-Host "  • Self-contained: no external scripts are invoked." -ForegroundColor White
    Write-Host "  • Module import: tries Microsoft.Hpc from well-known paths, then by name." -ForegroundColor White
    Write-Host "  • Graceful degrade: HPC features skip when the module isn't available." -ForegroundColor White
    Write-Host "  • Positional args supported: <Mode> [<headnode>] plus named options." -ForegroundColor White
    Write-Host "  • Script name in help is dynamic via $PSCommandPath or MyInvocation." -ForegroundColor White

    Write-Section "Module import candidates" 'Cyan'
    Write-Host "  C:\\Program Files\\Microsoft HPC Pack 2019\\PowerShell\\Microsoft.Hpc.dll" -ForegroundColor Gray
    Write-Host "  C:\\Program Files\\Microsoft HPC Pack 2016\\PowerShell\\Microsoft.Hpc.dll" -ForegroundColor Gray

    Write-Section "HPC PowerShell cmdlets (Get-Command '*-Hpc*')" 'Cyan'
    try { $null = Import-HpcModule -Quiet } catch {}
    $cmds = @()
    try { $cmds = @(Get-Command *-Hpc* -ErrorAction SilentlyContinue) } catch { $cmds = @() }
    if ($cmds -and $cmds.Count -gt 0) {
        Write-Host ("  {0} cmdlets found:" -f $cmds.Count) -ForegroundColor White
        try {
            $names = $cmds | Sort-Object Name | Select-Object -ExpandProperty Name
            $fw = $names | Format-Wide -Column 3 | Out-String -Width 200
            if ($fw) {
                $fw.TrimEnd().Split([Environment]::NewLine) | ForEach-Object {
                    if ($_ -and $_.Trim()) { Write-Host ("  " + $_) -ForegroundColor Gray }
                }
            }
        } catch {
            # fallback simple list
            $names = $cmds | Sort-Object Name | Select-Object -ExpandProperty Name
            foreach ($n in $names) { Write-Host ("  " + $n) -ForegroundColor Gray }
        }
    }
    else {
        Write-Host "  (No *-Hpc* cmdlets found. Ensure the Microsoft.Hpc module is installed and available.)" -ForegroundColor Yellow
    }

    Write-Section "RunMode details" 'Cyan'
    Write-Host "  All:" -ForegroundColor Yellow
    Write-Host "    Runs every internal section in order." -ForegroundColor White
    Write-Host "  NetworkFix:" -ForegroundColor Yellow
    Write-Host "    Checks: default route reachability, DNS resolution (microsoft.com, azure.com)." -ForegroundColor White
    Write-Host "    Repairs (when -FixNetworkIssues): netsh winsock reset; ipconfig /flushdns;" -ForegroundColor White
    Write-Host "    opens inbound firewall TCP ports: 80, 443, 9087, 9090, 9091, 9094." -ForegroundColor White
    Write-Host "  PortTest:" -ForegroundColor Yellow
    Write-Host "    Tests TCP connectivity to a node. -Port <int> for single port, -Ports <int[]> for list/range." -ForegroundColor White
    Write-Host "    Defaults: target is -NodeName if provided else -SchedulerNode;" -ForegroundColor White
    Write-Host "    ports default to 80, 443, 9087, 9090, 9091, 9094 when none are specified." -ForegroundColor White
    Write-Host "  CommandTest:" -ForegroundColor Yellow
    Write-Host "    Uses Get-HpcClusterOverview to validate connectivity and list version/node count." -ForegroundColor White
    Write-Host "  NodeValidation:" -ForegroundColor Yellow
    Write-Host "    Uses Get-HpcNode; summarizes Online/Healthy and lists first 10 non-OK nodes." -ForegroundColor White
    Write-Host "  NodeConfig:" -ForegroundColor Yellow
    Write-Host "    Reads HKLM:\\SOFTWARE\\Microsoft\\HPC for InstalledRole, SSLThumbprint, ClusterConnectionString." -ForegroundColor White
    Write-Host "  ClusterMetadata:" -ForegroundColor Yellow
    Write-Host "    Cluster overview via Get-HpcClusterOverview (name, version, nodes)." -ForegroundColor White
    Write-Host "  NodeTemplates:" -ForegroundColor Yellow
    Write-Host "    Counts templates and groups via Get-HpcNodeTemplate and Get-HpcGroup." -ForegroundColor White
    Write-Host "  JobHistory:" -ForegroundColor Yellow
    Write-Host "    Shows up to 10 recent jobs via Get-HpcJob -State All (prints first 5)." -ForegroundColor White
    Write-Host "    -JobId N: prints detailed job info via Get-HpcJobDetails, including tasks and ErrorMessage." -ForegroundColor White
    Write-Host "    -NodeName NAME [-DaysBack N]: prints node state history (Get-HpcNodeStateHistory)." -ForegroundColor White
    Write-Host "    If only -JobId is supplied, attempts to infer a node from AllocatedNodes and prints its history." -ForegroundColor White
    Write-Host "  NodeHistory:" -ForegroundColor Yellow
    Write-Host "    Prints node state history via Get-HpcNodeStateHistory for a node." -ForegroundColor White
    Write-Host "    Usage: NodeHistory <NodeName> [-DaysBack N] (defaults to 7)." -ForegroundColor White
    Write-Host "    If -NodeName isn't provided, uses the positional SchedulerNode as the target node." -ForegroundColor White
    Write-Host "  ClusterMetrics:" -ForegroundColor Yellow
    Write-Host "    Counts available metrics via Get-HpcMetric." -ForegroundColor White
    Write-Host "  MetricValueHistory:" -ForegroundColor Yellow
    Write-Host "    Exports metric value history (Get-HpcMetricValueHistory) to CSV." -ForegroundColor White
    Write-Host "    Options: -MetricStartDate <DateTime>, -MetricEndDate <DateTime>, -MetricOutputPath <Path>." -ForegroundColor White
    Write-Host "    Defaults: last 7 days if dates not specified; end defaults to now." -ForegroundColor White
    Write-Host "  ClusterTopology:" -ForegroundColor Yellow
    Write-Host "    Pings first 5 nodes' NetBIOS names from Get-HpcNode; shows reachability/state/health." -ForegroundColor White
    Write-Host "  ServicesStatus:" -ForegroundColor Yellow
    Write-Host "    Summarizes Windows services with DisplayName like '*HPC*'." -ForegroundColor White
    Write-Host "  DiagnosticTests:" -ForegroundColor Yellow
    Write-Host "    Counts tests via Get-HpcTest; invokes CCP_HOME\\Bin\\HpcDiagnosticHost.exe certtest if present." -ForegroundColor White
    Write-Host "  SystemInfo:" -ForegroundColor Yellow
    Write-Host "    OS and hardware via Win32_OperatingSystem and Win32_ComputerSystem." -ForegroundColor White
    Write-Host "  AdvancedHealth:" -ForegroundColor Yellow
    Write-Host "    Samples CPU and memory via Get-Counter." -ForegroundColor White
    Write-Section "Positional examples" 'Cyan'
    Write-Host "  .\\$Script:SelfName ClusterTopology" -ForegroundColor White
    Write-Host "  .\\$Script:SelfName ClusterTopology headnode -FixNetworkIssues" -ForegroundColor White
}

function Show-RunModeHelp {
    param(
        [Parameter(Mandatory=$true)][string]$RunMode,
        [switch]$DeepHelp
    )
    Write-Header 'RUN MODE HELP'
    $name = $RunMode
    $modes = Get-InsightRunModes
    $meta = $modes | Where-Object { $_.Name -ieq $name } | Select-Object -First 1
    if (-not $meta) { Write-Host ("Unknown run mode: {0}" -f $name) -ForegroundColor Yellow; return }
    Write-Section ("{0}" -f $meta.Name) 'Cyan'
    Write-Host ("Description: {0}" -f $meta.Description) -ForegroundColor White
    Write-Host "" -ForegroundColor White
    Write-Host "Usage:" -ForegroundColor Green
    switch ($meta.Name) {
        'NodeHistory' {
            Write-Host ("  .\{0} NodeHistory <NodeName> [-DaysBack N]" -f $Script:SelfName) -ForegroundColor White
            Write-Host ("  If -NodeName isn't provided, uses the positional SchedulerNode as the target node.") -ForegroundColor White
        }
        'JobHistory' {
            Write-Host ("  .\{0} JobHistory [-JobId N] [-NodeName NAME] [-DaysBack N] [-SchedulerNode HEADNODE]" -f $Script:SelfName) -ForegroundColor White
            Write-Host ("  With -JobId: prints details for the job. With -NodeName: also prints node state history.") -ForegroundColor White
        }
        'NetworkFix' {
            Write-Host ("  .\{0} NetworkFix [-FixNetworkIssues] [-SchedulerNode HEADNODE]" -f $Script:SelfName) -ForegroundColor White
            Write-Host ("  -FixNetworkIssues runs winsock reset, DNS flush, and opens core ports.") -ForegroundColor White
            Write-Host "" -ForegroundColor White
            Write-Host "Optional sub-operations:" -ForegroundColor Green
            Write-Host ("  -TestHpcNodePorts [-NodeName NAME] [-Port <int>] [-Ports <int[]>]    Test TCP ports (single or range)" ) -ForegroundColor White
            Write-Host ("  Examples:" ) -ForegroundColor White
            Write-Host ("    .\{0} NetworkFix -TestHpcNodePorts -NodeName IaaSCN104 -Port 40002" -f $Script:SelfName) -ForegroundColor Cyan
            Write-Host ("    .\{0} NetworkFix -TestHpcNodePorts -NodeName IaaSCN104 -Ports @(40000..40003)" -f $Script:SelfName) -ForegroundColor Cyan
        }
        'PortTest' {
            Write-Host ("  .\{0} PortTest [-SchedulerNode HEADNODE] [-NodeName NAME] [-Port <int>] [-Ports <int[]>]" -f $Script:SelfName) -ForegroundColor White
            Write-Host ("  Test a single port (-Port) or a range/list (-Ports)") -ForegroundColor White
            Write-Host ("  Examples:") -ForegroundColor White
            Write-Host ("    .\{0} PortTest -NodeName IaaSCN104 -Port 40000" -f $Script:SelfName) -ForegroundColor Cyan
            Write-Host ("    .\{0} PortTest -NodeName IaaSCN104 -Ports @(40000..40003)" -f $Script:SelfName) -ForegroundColor Cyan
        }
        'MetricValueHistory' {
            Write-Host ("  .\{0} MetricValueHistory [-SchedulerNode HEADNODE] [-MetricStartDate <DateTime>] [-MetricEndDate <DateTime>] [-MetricOutputPath <Path>]" -f $Script:SelfName) -ForegroundColor White
            Write-Host ("  Examples:") -ForegroundColor White
            Write-Host ("    .\{0} MetricValueHistory -Verbose   # export last 7 days to CSV" -f $Script:SelfName) -ForegroundColor White
            Write-Host ("    .\{0} MetricValueHistory -MetricStartDate '2025-08-01' -MetricEndDate '2025-08-14' -MetricOutputPath C:\\temp\\mvh.csv" -f $Script:SelfName) -ForegroundColor White
            Write-Host ("    .\{0} MetricValueHistory -MetricStartDate (Get-Date).AddDays(-3)   # end defaults to now" -f $Script:SelfName) -ForegroundColor White
        }
        'All' {
            Write-Host ("  .\{0} All [-SchedulerNode HEADNODE]" -f $Script:SelfName) -ForegroundColor White
        }
        default {
            Write-Host ("  .\{0} {1} [-SchedulerNode HEADNODE]" -f $Script:SelfName, $meta.Name) -ForegroundColor White
        }
    }
    if ($DeepHelp) {
        Write-Host ""; Write-Host "Notes:" -ForegroundColor Green
        switch ($meta.Name) {
            'NodeHistory' {
                Write-Host "  Prints node state history via Get-HpcNodeStateHistory for a node." -ForegroundColor White
                Write-Host "  Defaults to last 7 days; adjust with -DaysBack." -ForegroundColor White
            }
            'JobHistory' {
                Write-Host "  Shows recent jobs; -Verbose adds stats and templates." -ForegroundColor White
                Write-Host "  Also tries to infer a node from -JobId to show its history." -ForegroundColor White
            }
            'NetworkFix' {
                Write-Host "  Tests default gateway and DNS; -FixNetworkIssues performs repairs." -ForegroundColor White
            }
            'MetricValueHistory' {
                Write-Host "  Exports historical metric values via Get-HpcMetricValueHistory." -ForegroundColor White
                Write-Host "  Defaults: StartDate=(now-7 days), EndDate=now, OutputPath=MetricValueHistory.csv." -ForegroundColor White
                Write-Host "  Provide -MetricStartDate and optionally -MetricEndDate/-MetricOutputPath to customize." -ForegroundColor White
                Write-Host "  Use -CliTips to print only the PowerShell tips, or -Verbose for tips plus a preview." -ForegroundColor White
            }
            default {
                Write-Host "  Use -Verbose for deeper output where supported by this mode." -ForegroundColor White
            }
        }
    }
}

function Invoke-InsightRunMode {
    param(
        [string]$RunMode,
    [string]$SchedulerNode
    )

    switch ($RunMode) {
    'ListRunModes' {
            if (-not $Script:CliTipsOnly) { Write-Header 'AVAILABLE RUN MODES' }
            Get-InsightRunModes | ForEach-Object {
                if (-not $Script:CliTipsOnly) { Write-Host ("  {0,-16} {1} [{2}]" -f $_.Name, $_.Description, $_.Source) -ForegroundColor White }
            }
            return
        }
    'All' {
            Import-HpcModule -Quiet | Out-Null
            if (-not $Script:CliTipsOnly) { Write-Header 'RUNNING: All' }
            Invoke-SystemInfo
            Invoke-ServicesStatus
            Invoke-SqlTrace
            Invoke-NetworkFix
            Invoke-PortTest
            Invoke-CommandTest
            Invoke-NodeValidation
            Invoke-ClusterMetadata
            Invoke-NodeTemplates
            Invoke-JobHistory
            # Include NodeHistory as part of All. If -NodeName isn't provided, use SchedulerNode.
            $targetNode = if ($NodeName) { $NodeName } else { $SchedulerNode }
            Invoke-NodeHistory -NodeName $targetNode -DaysBack $DaysBack
            Invoke-ClusterMetrics
            $mvhArgs = @{}
            if ($PSBoundParameters.ContainsKey('MetricStartDate')) { $mvhArgs.StartDate = $MetricStartDate }
            if ($PSBoundParameters.ContainsKey('MetricEndDate'))   { $mvhArgs.EndDate   = $MetricEndDate }
            if ($PSBoundParameters.ContainsKey('MetricOutputPath')){ $mvhArgs.OutputPath= $MetricOutputPath }
            Invoke-MetricValueHistory @mvhArgs
            Invoke-ClusterTopology
            Invoke-DiagnosticTests
            Invoke-NodeConfig
            Invoke-CommunicationTest
            Invoke-AdvancedHealth
            return
        }
        'NetworkFix' {
            Import-HpcModule -Quiet | Out-Null
            if (-not $Script:CliTipsOnly) { Write-Header 'RUNNING: NetworkFix' }
            Invoke-NetworkFix
            return
        }
        'PortTest' {
            Import-HpcModule -Quiet | Out-Null
            if (-not $Script:CliTipsOnly) { Write-Header 'RUNNING: PortTest' }
            Invoke-PortTest
            return
        }
        'CommandTest' {
            Import-HpcModule -Quiet | Out-Null
            if (-not $Script:CliTipsOnly) { Write-Header 'RUNNING: CommandTest' }
            Invoke-CommandTest
            return
        }
        'CommunicationTest' {
            Import-HpcModule -Quiet | Out-Null
         
            if (-not $Script:CliTipsOnly) { Write-Header 'RUNNING: CommunicationTest' }
            Invoke-CommunicationTest
            return
        }
        'NodeHistory' {
            Import-HpcModule -Quiet | Out-Null
            if (-not $Script:CliTipsOnly) { Write-Header 'RUNNING: NodeHistory' }
            # If -NodeName was not provided, treat SchedulerNode as the node target for convenience
            $targetNode = if ($NodeName) { $NodeName } else { $SchedulerNode }
            Invoke-NodeHistory -NodeName $targetNode -DaysBack $DaysBack
            return
        }
        'NodeValidation' {
            Import-HpcModule -Quiet | Out-Null
            Write-Header 'RUNNING: NodeValidation'
            Invoke-NodeValidation
            return
        }
        'ListModules' {
            $cliTipModes = @(
                'PortTest','NetworkFix','CommandTest','NodeValidation','NodeConfig','ClusterMetadata','NodeTemplates','JobHistory','JobDetails','ClusterMetrics','MetricValueHistory','ClusterTopology','ServicesStatus','DiagnosticTests','SystemInfo','AdvancedHealth','NodeHistory','CommunicationTest','SQLTrace'
            )
            Write-Host "RUN MODES IMPLEMENTED:" -ForegroundColor Yellow
            foreach ($m in $cliTipModes) { Write-Host "  $m" -ForegroundColor White }
            return
        }
    default {
            Import-HpcModule -Quiet | Out-Null
    if ($RunMode -in @('NodeConfig','ClusterMetadata','NodeTemplates','JobHistory','JobDetails','ClusterMetrics','MetricValueHistory','ClusterTopology','ServicesStatus','DiagnosticTests','SystemInfo','AdvancedHealth','NodeHistory','CommunicationTest','SQLTrace')) {
                if (-not $Script:CliTipsOnly) { Write-Header ("RUNNING: {0}" -f $RunMode) }
                switch ($RunMode) {
                    'NodeConfig'       { Invoke-NodeConfig }
                    'ClusterMetadata'  { Invoke-ClusterMetadata }
                    'NodeTemplates'    { Invoke-NodeTemplates }
                    'JobHistory'       { Invoke-JobHistory }
                    'JobDetails'       { Invoke-JobDetails -JobId $JobId }
                    'ClusterMetrics'   { Invoke-ClusterMetrics }
                    'MetricValueHistory' {
                        $mvhArgs2 = @{}
                        if ($PSBoundParameters.ContainsKey('MetricStartDate')) { $mvhArgs2.StartDate = $MetricStartDate }
                        if ($PSBoundParameters.ContainsKey('MetricEndDate'))   { $mvhArgs2.EndDate   = $MetricEndDate }
                        if ($PSBoundParameters.ContainsKey('MetricOutputPath')){ $mvhArgs2.OutputPath= $MetricOutputPath }
                        Invoke-MetricValueHistory @mvhArgs2
                    }
                    'ClusterTopology'  { Invoke-ClusterTopology }
                    'ServicesStatus'   { Invoke-ServicesStatus }
                    'DiagnosticTests'  { Invoke-DiagnosticTests }
                    'SystemInfo'       { Invoke-SystemInfo }
                    'AdvancedHealth'   { Invoke-AdvancedHealth }
            'NodeHistory'      { $tn = if ($NodeName) { $NodeName } else { $SchedulerNode }; Invoke-NodeHistory -NodeName $tn -DaysBack $DaysBack }
        'CommunicationTest' { Invoke-CommunicationTest }
        'SQLTrace'          { Invoke-SqlTrace }
                }
                return
            }
            else {
                throw "Unknown RunMode: $RunMode"
            }
        }
    }
}

if ($ShowHelp) {
    if ($PSBoundParameters.ContainsKey('RunMode') -and $RunMode) {
        Show-RunModeHelp -RunMode $RunMode -DeepHelp:$DeepHelp
    } else {
        Show-InsightHelp
        if ($DeepHelp) { Show-DeepHelp }
    }
    exit 0
}

# If -RunMode wasn't explicitly provided, avoid defaulting to 'All'.
# Support quick paths (-JobId or -NodeName). Otherwise, show help and exit.
if (-not $PSBoundParameters.ContainsKey('RunMode')) {
    if ($Script:CliTipsOnly) {
        # In tips-only mode, default to All so we print all modes' tips
        $RunMode = 'All'
    } else {
    try { Import-HpcModule -Quiet | Out-Null } catch {}
    if ($PSBoundParameters.ContainsKey('JobId') -and $JobId -gt 0) {
        Invoke-JobDetails -JobId $JobId
        return
    }
    elseif ($PSBoundParameters.ContainsKey('NodeName') -and $NodeName) {
        Invoke-NodeHistory -NodeName $NodeName -DaysBack $DaysBack
        return
    }
    elseif ($EnableMpiTesting) {
        Invoke-MpiSmokeTest
        return
    }
    else {
        Write-Host "No RunMode specified. Use -RunMode <Mode>, or pass -JobId / -NodeName for quick queries." -ForegroundColor Yellow
        Show-InsightHelp
        exit 1
    }
    }
}

# Handle transcript export if requested
$transcriptStarted = $false
if ($ExportToFile) {
    try {
        $logPath = $ReportFile
        if (-not [System.IO.Path]::IsPathRooted($logPath)) {
            $logPath = Join-Path -Path (Get-Location) -ChildPath $logPath
        }
        # Ensure parent directory exists
        $parent = Split-Path -Path $logPath -Parent
        if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -Path $parent -ItemType Directory -Force | Out-Null }
        Start-Transcript -Path $logPath -Append -ErrorAction Stop | Out-Null
        $transcriptStarted = $true
        Write-Host ("Logging transcript to: {0}" -f $logPath) -ForegroundColor Cyan
    } catch {
        Write-Host ("Could not start transcript: {0}" -f $_.Exception.Message) -ForegroundColor Yellow
    }
}

try {
    Invoke-InsightRunMode -RunMode $RunMode -SchedulerNode $SchedulerNode
    # If -JobId was also supplied, print job details after the selected run mode(s)
    if ($PSBoundParameters.ContainsKey('JobId') -and $JobId -gt 0) {
        Invoke-JobDetails -JobId $JobId
    }
    # If MPI testing requested, run a quick smoke test post-run
    if ($EnableMpiTesting) {
        Invoke-MpiSmokeTest
    }
} finally {
    if ($transcriptStarted) {
        try { Stop-Transcript | Out-Null } catch {}
    }
}

