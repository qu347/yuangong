param(
    [string]$DeviceId,
    [string]$ConfigFile
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw "Missing flutter command. Install Flutter and add it to PATH."
}

$RepositoryRoot = Split-Path -Parent $PSScriptRoot
$FlutterRoot = Join-Path $RepositoryRoot "apps\employee_app"
if ([string]::IsNullOrWhiteSpace($ConfigFile)) {
    $ConfigFile = Join-Path $RepositoryRoot "config\dev.android-emulator.json"
}
$ResolvedConfig = (Resolve-Path -LiteralPath $ConfigFile).Path

$Arguments = @("run", "--dart-define-from-file=$ResolvedConfig")
if (-not [string]::IsNullOrWhiteSpace($DeviceId)) {
    $Arguments += @("-d", $DeviceId)
}

Write-Host "==> Starting Flutter with Android config: $ResolvedConfig"
Push-Location $FlutterRoot
try {
    & flutter @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Flutter Android exited with code $LASTEXITCODE."
    }
} finally {
    Pop-Location
}
