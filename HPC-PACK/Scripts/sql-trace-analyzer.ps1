<#
.SYNOPSIS
  Analyzes SQL Server Extended Events (.xel) traces produced by sql-trace-collector.ps1 and prints a quick peek, full rows, distinct client apps, a pattern-based verification, and a workload summary.

.DESCRIPTION
  Reads one or more .xel files (supports exact file, folder, or wildcard) with sys.fn_xe_file_target_read_file and emits:
    - Sanity peek (latest 10 rows)
    - Full rows (latest first)
    - Distinct client applications
    - Verification sample filtered by -VerifyLike pattern
    - Summary grouped by truncated SQL text with counts and timings

.PARAMETER ServerInstance
  SQL Server host or host\instance to run the queries against. If not provided, the script auto-detects it from HKLM:\SOFTWARE\Microsoft\HPC\Security HAStorageDbConnectionString. If no instance is detected, the script will stop and request a server instance.

.PARAMETER XeFile
  Optional .xel path, folder, or wildcard. Defaults to 'HPC_QuickTrace.xel' in the current working directory. If a folder is passed, '*.xel' is used.

.PARAMETER VerifyLike
  T-SQL LIKE pattern used in the verification sample. Default: %SERVERPROPERTY%.

.EXAMPLE
  .\sql-trace-analyzer.ps1 -ServerInstance HN01 -XeFile C:\Temp\HPC_QuickTrace.xel

.EXAMPLE
  .\sql-trace-analyzer.ps1 -ServerInstance headnode\COMPUTECLUSTER -XeFile C:\Temp\TraceFolder -VerifyLike "%SELECT Job%"

.LINK
  Extended Events in SQL Server
  https://learn.microsoft.com/sql/relational-databases/extended-events/extended-events

.NOTES
  Requires the SqlServer PowerShell module (Install-Module SqlServer). Runs on Windows PowerShell 5.1 or later.
  
  Author         : Ricardo S Jacomini
  Team           : Azure HPC + AI  
  Email          : ricardo.jacomini@microsoft.com
  Version        : 0.1.0
  Last Modified  : 2025-09-02
  Script Name    : sql-trace-analyzer.ps1
#>

param(
  [Alias('h','help','?')][switch]$ShowHelp,    # Quick help: -h, -help, -?, -ShowHelp
  [string]$ServerInstance = "",               # Optional: auto-detected from HPC registry if not supplied
  [string]$XeFile   = "",                     # Optional: defaults to .\HPC_QuickTrace.xel in current directory
  [string]$VerifyLike = "%SERVERPROPERTY%"    # Change to what you care about, e.g. "%SELECT Job%"
)

# Show help and exit early when requested
if ($ShowHelp) {
  try {
    Get-Help -Full $PSCommandPath
  } catch {
    Write-Host "Usage: .\sql-trace-analyzer.ps1 [-ServerInstance <host\\instance>] [-XeFile <path|folder|pattern>] [-VerifyLike <pattern>]" -ForegroundColor Cyan
    Write-Host "Examples:" -ForegroundColor Cyan
    Write-Host "  .\sql-trace-analyzer.ps1" 
    Write-Host "  .\sql-trace-analyzer.ps1 -ServerInstance headnode\\COMPUTECLUSTER -XeFile C:\\Temp\\TraceFolder -VerifyLike \"%SELECT Job%\""
  }
  return
}

# Ensure SqlServer module
if (-not (Get-Module -ListAvailable -Name SqlServer)) {
  Install-Module -Name SqlServer -Scope CurrentUser -Force -AllowClobber
}
Import-Module SqlServer -ErrorAction Stop

function Get-HpcDbConnectionString {
  [OutputType([string])]
  param()
  # Match collector behavior exactly
  $path = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\HPC\Security'
  $name = 'HAStorageDbConnectionString'
  try {
    $v = (Get-ItemProperty -Path $path -Name $name -ErrorAction Stop).$name
    if ($v) { Write-Host "🔍 Found connection string at $path\\$name"; return $v }
  } catch {}
  return $null
}

# Auto-detect ServerInstance and trusted connection string from HPC registry when not provided
$trustedConnFromReg = $null
$connectionString = Get-HpcDbConnectionString
if ($connectionString) {
  $csbFull = New-Object System.Data.SqlClient.SqlConnectionStringBuilder $connectionString
  $csbFull.TrustServerCertificate = $true
  $trustedConnFromReg = $csbFull.ConnectionString
  if ([string]::IsNullOrWhiteSpace($ServerInstance) -and $csbFull["Data Source"]) {
    $ServerInstance = [string]$csbFull["Data Source"]
    Write-Host ("✅ Extracted server name: {0}" -f $ServerInstance)
  }
}

# Ensure we have a server and connection string (server mode only)
$connString = $null
if ($trustedConnFromReg) {
  $connString = $trustedConnFromReg
} elseif (-not [string]::IsNullOrWhiteSpace($ServerInstance)) {
  $csb = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
  $csb["Data Source"] = $ServerInstance
  $csb["Integrated Security"] = $true
  $csb["TrustServerCertificate"] = $true
  $connString = $csb.ConnectionString
} else {
  throw "ServerInstance not detected. Provide -ServerInstance or ensure the HPC registry connection string exists."
}

# Default to HPC_QuickTrace.xel in the current working directory
if ([string]::IsNullOrWhiteSpace($XeFile)) {
  $XeFile = Join-Path (Get-Location).Path "HPC_QuickTrace.xel"
}

# Normalize to wildcard (so you can pass a segment, folder, or exact file)
$xePattern = $XeFile
if (Test-Path $XeFile -PathType Container) {
  $xePattern = (Join-Path $XeFile "*.xel")
} elseif ($XeFile -match "_\d+_\d+\.xel$") {
  $xePattern = ($XeFile -replace "_\d+_\d+\.xel$", "*.xel")
} elseif ($XeFile -notlike "*.xel") {
  $xePattern = "$XeFile*.xel"
}

Write-Host "📁 Reading XE files with pattern: $xePattern"

# Local mode removed: this script now analyzes .xel via SQL Server only.

# 0) Sanity peek (latest 10, no filters)
$queryPeek = @"
;WITH src AS (
  SELECT CONVERT(XML, event_data) AS x
  FROM sys.fn_xe_file_target_read_file(N'$xePattern', NULL, NULL, NULL)
)
SELECT TOP (10)
  x.value('(event/@name)[1]','nvarchar(100)') AS event_name,
  x.value('(event/@timestamp)[1]','datetime2') AS utc_time,
  x.value('(event/action[@name=''client_app_name'']/value)[1]','nvarchar(128)') AS client_app_name,
  x.value('(event/action[@name=''client_hostname'']/value)[1]','nvarchar(128)') AS client_host,
  LEFT(x.value('(event/action[@name=''sql_text'']/value)[1]','nvarchar(max)'), 200) AS sql_text_sample
FROM src
ORDER BY utc_time DESC;
"@

# 1) Full rows
$queryRead = @"
;WITH src AS (
  SELECT CONVERT(XML, event_data) AS x
  FROM sys.fn_xe_file_target_read_file(N'$xePattern', NULL, NULL, NULL)
),
rows AS (
  SELECT
    DATEADD(HOUR, DATEDIFF(HOUR, GETUTCDATE(), SYSDATETIMEOFFSET()),
            x.value('(event/@timestamp)[1]','datetime2')) AS local_time,
    x.value('(event/@name)[1]','nvarchar(100)') AS event_name,
    x.value('(event/action[@name=''client_app_name'']/value)[1]','nvarchar(128)') AS client_app_name,
    x.value('(event/action[@name=''client_hostname'']/value)[1]','nvarchar(128)') AS client_host,
    x.value('(event/action[@name=''username'']/value)[1]','nvarchar(128)')        AS login_name,
    x.value('(event/action[@name=''database_name'']/value)[1]','sysname')         AS database_name,
    x.value('(event/action[@name=''sql_text'']/value)[1]','nvarchar(max)')        AS sql_text,
    TRY_CONVERT(float, x.value('(event/data[@name=''duration'']/value)[1]','bigint'))/1000.0 AS duration_ms
  FROM src
)
SELECT *
FROM rows
ORDER BY local_time DESC;
"@

# 2) Distinct client apps
$queryApps = @"
;WITH src AS (
  SELECT CONVERT(XML, event_data) AS x
  FROM sys.fn_xe_file_target_read_file(N'$xePattern', NULL, NULL, NULL)
)
SELECT DISTINCT
  x.value('(event/action[@name=''client_app_name'']/value)[1]','nvarchar(128)') AS client_app_name
FROM src
ORDER BY client_app_name;
"@

# 3) Verification (pattern only)
$queryVerify = @"
;WITH src AS (
  SELECT CONVERT(XML, event_data) AS x
  FROM sys.fn_xe_file_target_read_file(N'$xePattern', NULL, NULL, NULL)
),
rows AS (
  SELECT
    x.value('(event/@name)[1]','nvarchar(100)') AS event_name,
    x.value('(event/@timestamp)[1]','datetime2') AS utc_time,
    x.value('(event/action[@name=''client_app_name'']/value)[1]','nvarchar(128)') AS client_app_name,
    x.value('(event/action[@name=''sql_text'']/value)[1]','nvarchar(max)') AS sql_text
  FROM src
)
SELECT TOP (20) *
FROM rows
WHERE sql_text LIKE N'$VerifyLike'
ORDER BY utc_time DESC;
"@

# 4) Summary (by truncated SQL text)
$querySummary = @"
;WITH src AS (
  SELECT CONVERT(XML, event_data) AS x
  FROM sys.fn_xe_file_target_read_file(N'$xePattern', NULL, NULL, NULL)
),
rows AS (
  SELECT
    x.value('(event/action[@name=''client_app_name'']/value)[1]','nvarchar(128)') AS client_app_name,
    x.value('(event/action[@name=''sql_text'']/value)[1]','nvarchar(max)')       AS sql_text,
    TRY_CONVERT(bigint, x.value('(event/data[@name=''duration'']/value)[1]','bigint')) AS duration_us
  FROM src
)
SELECT
  client_app_name,
  CASE WHEN LEN(sql_text) <= 200 THEN sql_text ELSE LEFT(sql_text, 200) + N' …' END AS sql_text_sample,
  COUNT(*)                                     AS executions,
  SUM(duration_us) / 1000.0                    AS total_ms,
  AVG(CAST(duration_us AS float)) / 1000.0     AS avg_ms
FROM rows
GROUP BY client_app_name,
         CASE WHEN LEN(sql_text) <= 200 THEN sql_text ELSE LEFT(sql_text, 200) + N' …' END
ORDER BY total_ms DESC;
"@

Write-Host "`n👀 Sanity peek (latest 10, no filters):"
$peek = $null
try { $peek = Invoke-Sqlcmd -ConnectionString $connString -Query $queryPeek } catch {}
if ($peek) { $peek | Format-Table -AutoSize } else { Write-Host "(no rows)" }

Write-Host "`n🔎 Rows (latest first):"
$rows = $null
try { $rows = Invoke-Sqlcmd -ConnectionString $connString -Query $queryRead } catch {}
if ($rows) { $rows | Format-Table -AutoSize } else { Write-Host "(no rows)" }

Write-Host "`n🪪 Client apps seen in trace:"
$apps = $null
try { $apps = Invoke-Sqlcmd -ConnectionString $connString -Query $queryApps } catch {}
if ($apps) { $apps | Format-Table -AutoSize } else { Write-Host "(none)" }

Write-Host "`n✅ Verification (pattern only):"
$verify = $null
try { $verify = Invoke-Sqlcmd -ConnectionString $connString -Query $queryVerify } catch {}
if ($verify) { $verify | Format-Table -AutoSize } else { Write-Host "No matching rows found." }

Write-Host "`n📊 Summary (by total_ms, grouped by truncated text):"
$summary = $null
try { $summary = Invoke-Sqlcmd -ConnectionString $connString -Query $querySummary } catch {}
if ($summary) { $summary | Format-Table -AutoSize } else { Write-Host "(no rows)" }

# 5) Performance calculations (overall and by app)
$queryPerfWindow = @"
;WITH src AS (
  SELECT CONVERT(XML, event_data) AS x
  FROM sys.fn_xe_file_target_read_file(N'$xePattern', NULL, NULL, NULL)
)
SELECT
  COUNT(1) AS events,
  MIN(x.value('(event/@timestamp)[1]','datetime2')) AS utc_start,
  MAX(x.value('(event/@timestamp)[1]','datetime2')) AS utc_end,
  SUM(TRY_CONVERT(bigint, x.value('(event/data[@name=''duration'']/value)[1]','bigint'))) AS total_us,
  AVG(CAST(TRY_CONVERT(bigint, x.value('(event/data[@name=''duration'']/value)[1]','bigint')) AS float)) AS avg_us
FROM src;
"@

$queryPerfPercentiles = @"
;WITH src AS (
  SELECT CONVERT(XML, event_data) AS x
  FROM sys.fn_xe_file_target_read_file(N'$xePattern', NULL, NULL, NULL)
),
rows AS (
  SELECT TRY_CONVERT(bigint, x.value('(event/data[@name=''duration'']/value)[1]','bigint')) AS dur_us
  FROM src
  WHERE TRY_CONVERT(bigint, x.value('(event/data[@name=''duration'']/value)[1]','bigint')) IS NOT NULL
)
SELECT TOP (1)
  PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY dur_us) OVER() AS p50_us,
  PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY dur_us) OVER() AS p95_us,
  PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY dur_us) OVER() AS p99_us
FROM rows;
"@

$queryTopApps = @"
;WITH src AS (
  SELECT CONVERT(XML, event_data) AS x
  FROM sys.fn_xe_file_target_read_file(N'$xePattern', NULL, NULL, NULL)
),
rows AS (
  SELECT
    x.value('(event/action[@name=''client_app_name'']/value)[1]','nvarchar(128)') AS client_app_name,
    TRY_CONVERT(bigint, x.value('(event/data[@name=''duration'']/value)[1]','bigint')) AS duration_us
  FROM src
)
SELECT TOP (5)
  ISNULL(NULLIF(client_app_name, N''), N'(unknown)') AS client_app_name,
  COUNT(*) AS events,
  SUM(duration_us) / 1000.0 AS total_ms,
  AVG(CAST(duration_us AS float)) / 1000.0 AS avg_ms
FROM rows
GROUP BY ISNULL(NULLIF(client_app_name, N''), N'(unknown)')
ORDER BY total_ms DESC;
"@

Write-Host "`n⚙️ Performance overview:"
# Capture metrics for summary
$epsVal = $null; $avgVal = $null; $totalVal = $null
$p50ms = $null; $p95ms = $null; $p99ms = $null
$topAppName = $null
try {
  $win = Invoke-Sqlcmd -ConnectionString $connString -Query $queryPerfWindow
  if ($win -and $win.events -gt 0) {
    $utcStart = [datetime]$win.utc_start
    $utcEnd   = [datetime]$win.utc_end
    # Convert to local for display
    $localStart = [System.TimeZoneInfo]::ConvertTimeFromUtc($utcStart, [System.TimeZoneInfo]::Local)
    $localEnd   = [System.TimeZoneInfo]::ConvertTimeFromUtc($utcEnd, [System.TimeZoneInfo]::Local)
    $seconds = [math]::Max(1, [int]([timespan]::FromTicks(($utcEnd - $utcStart).Ticks).TotalSeconds))
  $eps = [math]::Round(($win.events / $seconds), 2)
  $epsVal = $eps
  $avgMs = $null
  if ($null -ne $win.avg_us) { $avgMs = [math]::Round(($win.avg_us / 1000.0), 3) }
  $avgVal = $avgMs
  $totalMs = $null
  if ($null -ne $win.total_us) { $totalMs = [math]::Round(($win.total_us / 1000.0), 1) }
  $totalVal = $totalMs
    Write-Host ("  Events.............: {0}" -f $win.events)
    Write-Host ("  Window (local).....: {0}  to  {1}" -f $localStart, $localEnd)
    Write-Host ("  Duration (sec).....: {0}" -f $seconds)
    Write-Host ("  Events/sec.........: {0}" -f $eps)
  if ($null -ne $avgMs) { Write-Host ("  Avg duration (ms)..: {0}" -f $avgMs) }
  if ($null -ne $totalMs) { Write-Host ("  Total duration (ms): {0}" -f $totalMs) }
  } else { Write-Host "  (no events)" }
} catch {
  Write-Host ("  Failed to compute window: {0}" -f $_.Exception.Message)
}

try {
  $pct = Invoke-Sqlcmd -ConnectionString $connString -Query $queryPerfPercentiles
  if ($pct) {
    $p50 = [math]::Round(($pct.p50_us / 1000.0), 3)
    $p95 = [math]::Round(($pct.p95_us / 1000.0), 3)
    $p99 = [math]::Round(($pct.p99_us / 1000.0), 3)
    $p50ms = $p50; $p95ms = $p95; $p99ms = $p99
    Write-Host ("  Latency p50/p95/p99: {0} / {1} / {2} ms" -f $p50, $p95, $p99)
  }
} catch { Write-Host ("  Percentiles unavailable: {0}" -f $_.Exception.Message) }

try {
  $appsTop = Invoke-Sqlcmd -ConnectionString $connString -Query $queryTopApps
  if ($appsTop) {
    Write-Host "`n  Top client apps by total_ms:"
    $appsTop | Format-Table -AutoSize
    try { $topAppName = ($appsTop | Select-Object -First 1 -ExpandProperty client_app_name) } catch {}
  }
} catch { Write-Host ("  Top apps unavailable: {0}" -f $_.Exception.Message) }

# 📝 Interpretive summary
Write-Host "`n📝 Summary of metrics"
if ($null -ne $epsVal) {
  $epsNote = if ($epsVal -lt 10) { 'Low throughput — likely idle.' } elseif ($epsVal -lt 100) { 'Moderate throughput — depends on expected load.' } else { 'High throughput — verify capacity.' }
  Write-Host ("Events/sec...........: {0}  {1}" -f $epsVal, $epsNote)
}
if ($null -ne $avgVal) {
  $avgNote = if ($avgVal -lt 1) { 'Very fast — excellent response time.' } elseif ($avgVal -lt 10) { 'Good — sub-10 ms.' } elseif ($avgVal -lt 100) { 'Okay — double-digit ms.' } else { 'Slow — investigate.' }
  Write-Host ("Avg duration (ms)....: {0}  {1}" -f $avgVal, $avgNote)
}
if ($null -ne $totalVal) {
  $totNote = if ($totalVal -lt 1000) { 'Total time across all events — low overall.' } elseif ($totalVal -lt 10000) { 'Total time across all events — moderate.' } else { 'Total time across all events — high.' }
  Write-Host ("Total duration (ms)..: {0}  {1}" -f $totalVal, $totNote)
}
if ($null -ne $p50ms -and $null -ne $p95ms -and $null -ne $p99ms) {
  if ($p99ms -lt 1) {
    Write-Host ("Percentiles..........: p50={0}, p95={1}, p99={2} ms  All percentiles are well under 1 ms, which is excellent." -f $p50ms, $p95ms, $p99ms)
  } else {
    Write-Host ("Percentiles..........: p50={0}, p95={1}, p99={2} ms" -f $p50ms, $p95ms, $p99ms)
  }
}
if ($topAppName) {
  $appNote = if ($topAppName -match 'SqlClient') { 'Common and efficient SQL client.' } else { '' }
  if ([string]::IsNullOrWhiteSpace($appNote)) { Write-Host ("Client App...........: {0}" -f $topAppName) } else { Write-Host ("Client App...........: {0} — {1}" -f $topAppName, $appNote) }
}
