$ErrorActionPreference = 'Stop'
$backendDir = Split-Path -Parent $PSScriptRoot
$projectDir = Split-Path -Parent $backendDir
$envFile = Join-Path $projectDir '.env.local'
$clusterDir = Join-Path $projectDir '.local-postgres/data'
$pgCtl = 'C:\Program Files\PostgreSQL\17\bin\pg_ctl.exe'

if (-not (Test-Path -LiteralPath $envFile)) {
    throw 'Local .env.local is missing. The existing PostgreSQL setup is required.'
}
if (-not (Test-Path -LiteralPath $clusterDir)) {
    throw 'Local PostgreSQL cluster is missing at .local-postgres/data.'
}
if (-not (Test-Path -LiteralPath $pgCtl)) {
    throw 'PostgreSQL 17 pg_ctl.exe was not found.'
}

$line = Get-Content -LiteralPath $envFile |
    Where-Object { $_ -match '^DATABASE_URL=' } |
    Select-Object -First 1
if (-not $line) { throw 'DATABASE_URL is missing from .env.local.' }
$env:DATABASE_URL = $line.Substring('DATABASE_URL='.Length)

try {
    $health = Invoke-RestMethod -Uri 'http://127.0.0.1:4783/api/health' -TimeoutSec 2
    if ($health.ok -eq $true -and $health.storage -eq 'postgresql') {
        $listener = Get-NetTCPConnection -LocalPort 4783 -State Listen -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($listener) {
            $runningApi = Get-Process -Id $listener.OwningProcess -ErrorAction SilentlyContinue
            $sourceDirs = @((Join-Path $backendDir 'lib'), (Join-Path $backendDir 'bin'))
            $latestSource = Get-ChildItem -LiteralPath $sourceDirs -Filter '*.dart' -Recurse -File |
                Sort-Object LastWriteTimeUtc -Descending |
                Select-Object -First 1
            if ($runningApi -and $latestSource -and
                $latestSource.LastWriteTimeUtc -gt $runningApi.StartTime.ToUniversalTime()) {
                throw "The AeroDesk backend on port 4783 is running old code (PID $($runningApi.Id)). Stop that backend window with Ctrl+C, then run npm start again."
            }
        }
        Write-Output 'AeroDesk backend is already running at http://127.0.0.1:4783. Start Flutter in another PowerShell window.'
        return
    }
} catch {
    if ($_.Exception.Message -like 'The AeroDesk backend on port 4783 is running old code*') {
        throw
    }
    # No healthy local API is running, so continue with normal startup.
}

& $pgCtl status -D $clusterDir *> $null
if ($LASTEXITCODE -ne 0) {
    # A fresh log avoids old log-file locks/ACLs after an interrupted Windows run.
    $logPath = (New-TemporaryFile).FullName
    & $pgCtl start -D $clusterDir -l $logPath -o '-c listen_addresses=127.0.0.1 -p 55432' -w
    if ($LASTEXITCODE -ne 0) {
        $startupDetails = (Get-Content -LiteralPath $logPath -Tail 8 -ErrorAction SilentlyContinue) -join [Environment]::NewLine
        throw "Local PostgreSQL could not start. Startup log: $logPath`n$startupDetails"
    }
}

Push-Location $backendDir
try {
    dart run bin/server.dart
    if ($LASTEXITCODE -ne 0) { throw "Dart backend exited with code $LASTEXITCODE." }
} finally {
    Pop-Location
    Remove-Item Env:DATABASE_URL -ErrorAction SilentlyContinue
}
