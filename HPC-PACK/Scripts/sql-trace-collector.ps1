<#
.SYNOPSIS
  Purpose: Collect a short SQL Server Extended Events trace focused on HPC Pack databases for quick diagnostics.

.DESCRIPTION
  How it works:
  - Reads the connection string from HKLM:\SOFTWARE\Microsoft\HPC\Security (value: HAStorageDbConnectionString) and extracts the SQL Server name.
  - Ensures the SqlServer PowerShell module is installed and imported.
  - Creates an Extended Events session (default name: HPC_QuickTrace) that captures:
    - Events: rpc_completed and sql_batch_completed
    - Actions: client_app_name, client_hostname, username, database_name, sql_text
    - Filter: only for databases HPCScheduler, HPCReporting, HPCManagement
  - Saves to an event_file target in the same folder as the script (50 MB max, 2 rollovers).
  - Executes a tiny read in each target DB (if it exists) to guarantee the trace has rows.
  - Collects for a configurable duration (default: 120 seconds), then stops the session.
  - Renames the newest .xel file to a stable name: HPC_QuickTrace.xel (in the script folder).
  - Prints a follow-up command to analyze it with sql-trace-analyzer.ps1.

.PARAMETER RegPath
  Registry path containing the HAStorageDbConnectionString value (default: HKLM:\SOFTWARE\Microsoft\HPC\Security).

.PARAMETER RegValueName
  Registry value name for the SQL connection string (default: HAStorageDbConnectionString).

.PARAMETER SessionName
  Extended Events session name (default: HPC_QuickTrace).

.PARAMETER CollectSeconds
  The number of seconds to collect events before stopping the session (default: 120).

.OUTPUTS
  A single HPC_QuickTrace.xel file next to the script, ready for analysis.

.NOTES
  Requirements:
  - Access to the SQL instance in the connection string.
  - PowerShell permissions to install/import the SqlServer module if not present.
#>

param(
  [Alias('h','help','?')][switch]$ShowHelp,
  [string]$RegPath      = "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\HPC\Security",
  [string]$RegValueName = "HAStorageDbConnectionString",
  [string]$SessionName  = "HPC_QuickTrace",
  [int]$CollectSeconds  = 120
)

# --- Show help and exit early when requested ---
if ($ShowHelp) {
  try {
    Get-Help -Full $PSCommandPath
  } catch {
  Write-Host "Usage: .\sql-trace-collector.ps1 [-RegPath <registry path>] [-RegValueName <value>] [-SessionName <name>] [-CollectSeconds <seconds>]" -ForegroundColor Cyan
    Write-Host "Examples:" -ForegroundColor Cyan
    Write-Host "  .\sql-trace-collector.ps1"
  Write-Host "  .\sql-trace-collector.ps1 -RegPath 'Registry::HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\HPC\\Security' -RegValueName 'HAStorageDbConnectionString' -SessionName 'HPC_QuickTrace' -CollectSeconds 180"
  }
  return
}

# --- Resolve connection string / server instance ---
$connectionString = (Get-ItemProperty -Path $RegPath).$RegValueName
if (-not $connectionString) { throw "HAStorageDbConnectionString not found at $RegPath" }

if ($connectionString -match "Data Source=([^;]+)") {
  $serverName = $matches[1]
  Write-Host "✅ Extracted server name: $serverName"
} else {
  throw "❌ Could not extract server name from connection string."
}

# Harden connection: trust server cert to avoid self-signed/enterprise CA chain issues during quick diagnostics
$csb = New-Object System.Data.SqlClient.SqlConnectionStringBuilder $connectionString
$csb.TrustServerCertificate = $true
$trustedConnectionString = $csb.ConnectionString

# --- Ensure SqlServer module ---
if (-not (Get-Module -ListAvailable -Name SqlServer)) {
  try { Install-Module -Name SqlServer -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop } catch {}
}
Import-Module SqlServer -ErrorAction Stop

# --- Save to the same folder as this script ---
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $scriptPath) { $scriptPath = (Get-Location).Path }

# NOTE: XE treats filename as a prefix and will append rollover/timestamp.
# We'll rename the newest file to a fixed name after STOP.
$xePrefix       = Join-Path $scriptPath $SessionName
$xeFixedName    = Join-Path $scriptPath "$SessionName.xel"  # final stable name after rename
Write-Host "📁 XE target (folder): $scriptPath"
Write-Host "📦 Final fixed name after stop: $xeFixedName"

# --- Predicate: only capture the 3 HPC DBs ---
$predDb = @"
WHERE (sqlserver.database_name = N'HPCScheduler'
    OR sqlserver.database_name = N'HPCReporting'
    OR sqlserver.database_name = N'HPCManagement')
"@

# --- Drop -> Create -> Start ---
$dropIfExists = "IF EXISTS (SELECT 1 FROM sys.server_event_sessions WHERE name = N'$SessionName') DROP EVENT SESSION [$SessionName] ON SERVER;"

$create = @"
CREATE EVENT SESSION [$SessionName] ON SERVER
ADD EVENT sqlserver.rpc_completed(
  ACTION(sqlserver.client_app_name, sqlserver.client_hostname, sqlserver.username, sqlserver.database_name, sqlserver.sql_text)
  $predDb
),
ADD EVENT sqlserver.sql_batch_completed(
  ACTION(sqlserver.client_app_name, sqlserver.client_hostname, sqlserver.username, sqlserver.database_name, sqlserver.sql_text)
  $predDb
)
ADD TARGET package0.event_file(
  SET filename = N'$xePrefix', max_file_size = (50), max_rollover_files = (2)
)
WITH (
  EVENT_RETENTION_MODE = ALLOW_SINGLE_EVENT_LOSS,
  TRACK_CAUSALITY      = ON,
  STARTUP_STATE        = OFF
);
"@

Invoke-Sqlcmd -ConnectionString $trustedConnectionString -Query $dropIfExists | Out-Null
Invoke-Sqlcmd -ConnectionString $trustedConnectionString -Query $create       | Out-Null
Invoke-Sqlcmd -ConnectionString $trustedConnectionString -Query "ALTER EVENT SESSION [$SessionName] ON SERVER STATE = START;" | Out-Null
Write-Host "✅ Extended Events session '$SessionName' started."

# --- Tiny workload in each target DB (so you always capture at least something) ---
#    Only runs if DB exists.
try {
  $conn = New-Object System.Data.SqlClient.SqlConnection $trustedConnectionString
  $conn.Open()
  $cmd = $conn.CreateCommand()

  $dbs = @('HPCScheduler','HPCReporting','HPCManagement')
  foreach ($db in $dbs) {
    $cmd.CommandText = "IF DB_ID(N'$db') IS NOT NULL BEGIN USE [$db]; SELECT DB_NAME() AS DbName, SERVERPROPERTY('ProductVersion') AS ProductVersion; END"
    try {
      $r = $cmd.ExecuteReader()
      while ($r.Read()) {
        Write-Host "🧪 Touched DB: $($r['DbName'])  Version: $($r['ProductVersion'])"
      }
      $r.Close()
    } catch {
      # ignore per-DB failures; continue
    }
  }

  $conn.Close()
} catch {
  Write-Error "❌ SQL workload failed: $_"
  Invoke-Sqlcmd -ConnectionString $trustedConnectionString -Query "ALTER EVENT SESSION [$SessionName] ON SERVER STATE = STOP;" | Out-Null
  throw
}

# --- Flush & Stop ---
Start-Sleep -Milliseconds 500 # just ping test
Start-Sleep -Seconds $CollectSeconds   # collect for configured duration (default 120s)

Invoke-Sqlcmd -ConnectionString $trustedConnectionString -Query "ALTER EVENT SESSION [$SessionName] ON SERVER STATE = STOP; WAITFOR DELAY '00:00:01';" | Out-Null
Write-Host "⏹️ Extended Events session '$SessionName' stopped."

# --- Rename newest segment to a timestamped name and also update fixed name (HPC_QuickTrace.xel) ---
$pattern = Join-Path $scriptPath ($SessionName + "_*.xel")
$latest = Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue |
          Sort-Object LastWriteTime -Descending |
          Select-Object -First 1

if ($latest) {
  $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
  $datedName = Join-Path $scriptPath ("{0}_{1}.xel" -f $SessionName, $timestamp)

  # First, move to a unique timestamped file to avoid name collisions
  try {
    Move-Item -Path $latest.FullName -Destination $datedName -Force
  } catch {
    # If move fails (e.g., due to locks), fallback to copy then remove original if possible
    try { Copy-Item -Path $latest.FullName -Destination $datedName -Force } catch {}
    try { Remove-Item -Path $latest.FullName -Force -ErrorAction SilentlyContinue } catch {}
  }

  # Then, copy/overwrite the fixed file name for convenience
  $fixedUpdated = $false
  try {
    Copy-Item -Path $datedName -Destination $xeFixedName -Force
    $fixedUpdated = $true
  } catch {
    try {
      Remove-Item -Path $xeFixedName -Force -ErrorAction SilentlyContinue
      Copy-Item -Path $datedName -Destination $xeFixedName -Force
      $fixedUpdated = $true
    } catch {
      Write-Warning "Could not update fixed file '$xeFixedName'. Last error: $($_.Exception.Message)"
    }
  }

  Write-Host "✅ Saved timestamped trace: $datedName"
  if ($fixedUpdated -and (Test-Path $xeFixedName)) {
    Write-Host "✅ Updated fixed name: $xeFixedName"
  }
} else {
  Write-Warning "No XE files found matching: $pattern"
}

Write-Host "✅ Done. Analyze with:"
Write-Host "   .\sql-trace-analyzer.ps1 "
Write-Host "   .\sql-trace-analyzer.ps1 -ServerInstance `"$serverName`" "
Write-Host "   .\sql-trace-analyzer.ps1 -ServerInstance `"$serverName`" -XeFile `"$xeFixedName`""
