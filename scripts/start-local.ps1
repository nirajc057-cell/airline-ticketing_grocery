param(
  [string]$PostgresBin = 'C:\Program Files\PostgreSQL\17\bin'
)

$ErrorActionPreference = 'Stop'
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$envFile = Join-Path $projectRoot '.env.local'
$dataDirectory = Join-Path $projectRoot '.local-postgres/data'
$logFile = Join-Path $projectRoot 'local-postgres.log'
$pgCtl = Join-Path $PostgresBin 'pg_ctl.exe'

if (-not (Test-Path -LiteralPath $envFile) -or -not (Test-Path -LiteralPath (Join-Path $dataDirectory 'PG_VERSION'))) {
  throw 'Local PostgreSQL is not configured. Run npm run local:setup first.'
}

foreach ($line in Get-Content -LiteralPath $envFile) {
  if ($line -match '^([A-Z_]+)=(.*)$') {
    [System.Environment]::SetEnvironmentVariable($matches[1], $matches[2], 'Process')
  }
}

if ($env:STORAGE_DRIVER -ne 'postgres' -or -not $env:DATABASE_URL) {
  throw 'The local configuration must select PostgreSQL and include DATABASE_URL.'
}

$databaseUri = [uri]$env:DATABASE_URL
if ($databaseUri.Host -ne '127.0.0.1' -or $databaseUri.AbsolutePath -ne '/aerodesk') {
  throw 'Refusing to start against a non-local or unexpected database.'
}

& $pgCtl -D $dataDirectory status *> $null
if ($LASTEXITCODE -ne 0) {
  & $pgCtl -D $dataDirectory -l $logFile -o "-h 127.0.0.1 -p $($databaseUri.Port)" -w start
  if ($LASTEXITCODE -ne 0) { throw 'Local PostgreSQL did not start. Check local-postgres.log.' }
}

Push-Location $projectRoot
try {
  Write-Output 'Starting the Flutter API with local PostgreSQL. Open http://localhost:4782/flutter/'
  & node (Join-Path $projectRoot 'server.js')
  exit $LASTEXITCODE
} finally { Pop-Location }
