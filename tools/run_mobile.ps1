param(
  [string]$DeviceId = ""
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $root "supabase.local.json"

if (-not (Test-Path $configPath)) {
  Write-Host "Missing supabase.local.json."
  Write-Host "Copy supabase.local.example.json to supabase.local.json, then fill in your Supabase URL and anon key."
  exit 1
}

$config = Get-Content $configPath -Raw | ConvertFrom-Json
$url = [string]$config.SUPABASE_URL
$anonKey = [string]$config.SUPABASE_ANON_KEY

if ([string]::IsNullOrWhiteSpace($url) -or [string]::IsNullOrWhiteSpace($anonKey)) {
  Write-Host "supabase.local.json must include SUPABASE_URL and SUPABASE_ANON_KEY."
  exit 1
}

$args = @(
  "run",
  "--dart-define=SUPABASE_URL=$url",
  "--dart-define=SUPABASE_ANON_KEY=$anonKey"
)

if (-not [string]::IsNullOrWhiteSpace($DeviceId)) {
  $args += @("-d", $DeviceId)
}

flutter @args
