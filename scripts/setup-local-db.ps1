param(
  [string]$PostgresBin = 'C:\Program Files\PostgreSQL\17\bin',
  [int]$DatabasePort = 55432
)

$ErrorActionPreference = 'Stop'
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$clusterRoot = Join-Path $projectRoot '.local-postgres'
$dataDirectory = Join-Path $clusterRoot 'data'
$envFile = Join-Path $projectRoot '.env.local'
$passwordFile = Join-Path $clusterRoot 'init-password.tmp'
$logFile = Join-Path $projectRoot 'local-postgres.log'
$initdb = Join-Path $PostgresBin 'initdb.exe'
$pgCtl = Join-Path $PostgresBin 'pg_ctl.exe'
$createdb = Join-Path $PostgresBin 'createdb.exe'
$psql = Join-Path $PostgresBin 'psql.exe'

foreach ($program in @($initdb, $pgCtl, $createdb, $psql)) {
  if (-not (Test-Path -LiteralPath $program)) {
    throw "PostgreSQL program not found: $program"
  }
}

if ((Test-Path -LiteralPath $envFile) -xor (Test-Path -LiteralPath (Join-Path $dataDirectory 'PG_VERSION'))) {
  throw 'Only part of the local database setup exists. Do not overwrite it; inspect .env.local and .local-postgres/data first.'
}

if (Test-Path -LiteralPath $envFile) {
  Write-Output 'Local PostgreSQL is already configured. Use npm run local:start.'
  exit 0
}

if ((Test-Path -LiteralPath $clusterRoot) -and (Get-ChildItem -LiteralPath $clusterRoot -Force | Select-Object -First 1)) {
  throw 'The local PostgreSQL directory already contains files without a complete setup. Refusing to overwrite it.'
}

if (-not (Test-Path -LiteralPath $clusterRoot)) {
  New-Item -ItemType Directory -Path $clusterRoot | Out-Null
}
$randomBytes = New-Object byte[] 32
$randomGenerator = [System.Security.Cryptography.RandomNumberGenerator]::Create()
try { $randomGenerator.GetBytes($randomBytes) } finally { $randomGenerator.Dispose() }
$databasePassword = [Convert]::ToBase64String($randomBytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
$utf8 = New-Object System.Text.UTF8Encoding($false)

try {
  [System.IO.File]::WriteAllText($passwordFile, "$databasePassword`n", $utf8)
  & $initdb -D $dataDirectory -U aerodesk -E UTF8 --locale=C --auth-local=scram-sha-256 --auth-host=scram-sha-256 --pwfile=$passwordFile --no-instructions
  if ($LASTEXITCODE -ne 0) { throw 'PostgreSQL initialization failed.' }
} finally {
  if (Test-Path -LiteralPath $passwordFile) {
    Remove-Item -LiteralPath $passwordFile -Force
  }
}

& $pgCtl -D $dataDirectory -l $logFile -o "-h 127.0.0.1 -p $DatabasePort" -w start
if ($LASTEXITCODE -ne 0) { throw 'Local PostgreSQL did not start. Check local-postgres.log.' }

$env:PGPASSWORD = $databasePassword
try {
  & $createdb -w -h 127.0.0.1 -p $DatabasePort -U aerodesk -E UTF8 -T template0 --locale=C aerodesk
  if ($LASTEXITCODE -ne 0) { throw 'Could not create the aerodesk database.' }

  $connectionUrl = "postgresql://aerodesk:$databasePassword@127.0.0.1:$DatabasePort/aerodesk"
  $env:DATABASE_URL = $connectionUrl
  $env:STORAGE_DRIVER = 'postgres'
  [System.IO.File]::WriteAllLines($envFile, @(
    "DATABASE_URL=$connectionUrl",
    'STORAGE_DRIVER=postgres',
    'PORT=4782'
  ), $utf8)
  if (Test-Path -LiteralPath (Join-Path $projectRoot 'data/store.json')) {
    $backupDirectory = Join-Path $clusterRoot 'backups'
    New-Item -ItemType Directory -Path $backupDirectory | Out-Null
    $backupName = 'store-before-sql-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.json'
    Copy-Item -LiteralPath (Join-Path $projectRoot 'data/store.json') -Destination (Join-Path $backupDirectory $backupName)
    Push-Location $projectRoot
    try {
      & node (Join-Path $projectRoot 'backend/migrate-json.js')
      if ($LASTEXITCODE -ne 0) { throw 'JSON to PostgreSQL migration failed.' }
    } finally { Pop-Location }
  }

  & $psql -w -h 127.0.0.1 -p $DatabasePort -U aerodesk -d aerodesk -t -c 'SELECT current_database(), current_setting(''server_encoding''), (SELECT count(*) FROM app_state)'
  if ($LASTEXITCODE -ne 0) { throw 'PostgreSQL verification failed.' }
  Write-Output 'Local SQL setup complete. Existing JSON data was imported, and .env.local is gitignored.'
  Write-Output 'Run npm run local:start, then open http://localhost:4782/flutter/'
} finally {
  Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
  Remove-Item Env:DATABASE_URL -ErrorAction SilentlyContinue
  Remove-Item Env:STORAGE_DRIVER -ErrorAction SilentlyContinue
}
