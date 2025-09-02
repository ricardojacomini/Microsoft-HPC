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
  
  Author         : Ricardo S Jacomini
  Team           : Azure HPC + AI  
  Email          : ricardo.jacomini@microsoft.com
  Version        : 0.1.0
  Last Modified  : 2025-09-02
  Script Name    : sql-trace-collector.ps1
#>

param(
  [Alias('h','help','?')][switch]$ShowHelp,
  [string]$RegPath      = "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\HPC\Security",
  [string]$RegValueName = "HAStorageDbConnectionString",
  [string]$SessionName  = "HPC_QuickTrace",
  [int]$CollectSeconds  = 120
)
Write-Host "=== Script started at $(Get-Date) ==="

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




Write-Host "Step: Resolving connection string from registry..."
$connectionString = (Get-ItemProperty -Path $RegPath).$RegValueName
Write-Host "  Connection string: $connectionString"
if (-not $connectionString) { throw "HAStorageDbConnectionString not found at $RegPath" }

if ($connectionString -match "Data Source=([^;]+)") {
  $serverName = $matches[1]
  Write-Host "✅ Extracted server name: $serverName"
} else {
  throw "❌ Could not extract server name from connection string."
}


Write-Host "Step: Building trusted connection string..."
$csb = New-Object System.Data.SqlClient.SqlConnectionStringBuilder $connectionString
$csb.TrustServerCertificate = $true
$trustedConnectionString = $csb.ConnectionString
Write-Host "  Trusted connection string: $trustedConnectionString"

Write-Host "Step: Ensuring SqlServer module is available..."
if (-not (Get-Module -ListAvailable -Name SqlServer)) {
  Write-Host "  SqlServer module not found, installing..."
  try { Install-Module -Name SqlServer -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop } catch { Write-Host "  Failed to install SqlServer module: $_" }
}
Write-Host "  Importing SqlServer module..."
Import-Module SqlServer -ErrorAction Stop

Write-Host "Step: Determining script path and XE file names..."
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $scriptPath) { $scriptPath = (Get-Location).Path }
Write-Host "  Script path: $scriptPath"

$xePrefix       = Join-Path $scriptPath $SessionName
$xeFixedName    = Join-Path $scriptPath "$SessionName.xel"
Write-Host "📁 XE target (folder): $scriptPath"
Write-Host "📦 Final fixed name after stop: $xeFixedName"

# --- Predicate: only capture the 3 HPC DBs ---
$predDb = @"
WHERE (sqlserver.database_name = N'HPCScheduler'
    OR sqlserver.database_name = N'HPCReporting'
    OR sqlserver.database_name = N'HPCManagement')
"@

# --- Drop -> Create -> Start ---
Write-Host "Step: Preparing XE session drop/create/start queries..."
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

Write-Host "Step: Dropping existing XE session (if any)..."
try {
  Invoke-Sqlcmd -ConnectionString $trustedConnectionString -Query $dropIfExists | Out-Null
  Write-Host "  Drop completed."
} catch {
  Write-Host "  Drop step encountered an error (continuing if not exists): $_"
}

Write-Host "Step: Creating XE session..."
try {
  Invoke-Sqlcmd -ConnectionString $trustedConnectionString -Query $create | Out-Null
  Write-Host "  Create completed."
} catch {
  Write-Host "  Create step failed: $_"
}

Write-Host "Step: Starting XE session..."
try {
  Invoke-Sqlcmd -ConnectionString $trustedConnectionString -Query "ALTER EVENT SESSION [$SessionName] ON SERVER STATE = START;" | Out-Null
  Write-Host "  Start completed."
} catch {
  Write-Host "  Start step failed (session may already be running): $_"
}
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
      Write-Host "    Failed to touch DB ${db}: $_"
    }
  }

  $conn.Close()
  Write-Host "  Tiny workload completed."

} catch {
  Write-Error "❌ SQL workload failed: $_"
  Invoke-Sqlcmd -ConnectionString $trustedConnectionString -Query "ALTER EVENT SESSION [$SessionName] ON SERVER STATE = STOP;" | Out-Null
  Write-Host "=== Script ended at $(Get-Date) ==="
  throw
}

Write-Host "Step: Sleeping for $CollectSeconds seconds to collect events..."
# Start-Sleep -Milliseconds 500
Start-Sleep -Seconds $CollectSeconds
Write-Host "  Sleep completed."

Write-Host "Step: Stopping XE session..."
try {
  Invoke-Sqlcmd -ConnectionString $trustedConnectionString -Query "ALTER EVENT SESSION [$SessionName] ON SERVER STATE = STOP; WAITFOR DELAY '00:00:01';" | Out-Null
  Write-Host "  Stop completed."
} catch {
  Write-Host "  Stop step failed (session may already be stopped): $_"
}
Write-Host "⏹️ Extended Events session '$SessionName' stopped."

Write-Host "Step: Renaming and copying XE files..."
$pattern = Join-Path $scriptPath ($SessionName + "_*.xel")
Write-Host "  Looking for XE files matching: $pattern"
$latest = Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue |
          Sort-Object LastWriteTime -Descending |
          Select-Object -First 1

if ($latest) {
  $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
  $datedName = Join-Path $scriptPath ("{0}_{1}.xel" -f $SessionName, $timestamp)

  # First, move to a unique timestamped file to avoid name collisions
  try {
    Write-Host "  Moving XE file to: $datedName"
    Move-Item -Path $latest.FullName -Destination $datedName -Force
    Write-Host "  Move completed."
  } catch {
    Write-Host "  Move failed, trying copy/remove fallback: $_"
    try { Copy-Item -Path $latest.FullName -Destination $datedName -Force; Write-Host "  Copy completed." } catch { Write-Host "  Copy failed: $_" }
    try { Remove-Item -Path $latest.FullName -Force -ErrorAction SilentlyContinue; Write-Host "  Remove completed." } catch { Write-Host "  Remove failed: $_" }
  }

  # Then, copy/overwrite the fixed file name for convenience
  $fixedUpdated = $false
  try {
    Write-Host "  Copying to fixed name: $xeFixedName"
    Copy-Item -Path $datedName -Destination $xeFixedName -Force
    $fixedUpdated = $true
    Write-Host "  Fixed name copy completed."
  } catch {
    Write-Host "  Fixed name copy failed, trying remove/copy fallback: $_"
    try {
      Remove-Item -Path $xeFixedName -Force -ErrorAction SilentlyContinue
      Copy-Item -Path $datedName -Destination $xeFixedName -Force
      $fixedUpdated = $true
      Write-Host "  Fixed name copy after remove completed."
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
Write-Host "=== Script ended at $(Get-Date) ==="