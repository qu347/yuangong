$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw "Missing flutter command. Install Flutter and add it to PATH."
}

$RepositoryRoot = Split-Path -Parent $PSScriptRoot
$FlutterRoot = Join-Path $RepositoryRoot "apps\employee_app"
$ConfigFile = Join-Path $RepositoryRoot "config\dev.windows.json"

Write-Host "==> Starting Flutter with the Windows development config"
Push-Location $FlutterRoot
try {
    flutter run -d windows "--dart-define-from-file=$ConfigFile"
    if ($LASTEXITCODE -ne 0) {
        throw "Flutter Windows exited with code $LASTEXITCODE."
    }
} finally {
    Pop-Location
}
