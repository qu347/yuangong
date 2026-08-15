$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepositoryRoot = Split-Path -Parent $PSScriptRoot
$BackendRoot = Join-Path $RepositoryRoot "backend"
. (Join-Path $PSScriptRoot "python-command.ps1")
$PythonCommand = Resolve-ProjectPython -BackendRoot $BackendRoot
$PythonExecutable = $PythonCommand.FilePath
$PythonPrefixArguments = @($PythonCommand.PrefixArguments)

Write-Warning "The server listens on 0.0.0.0:8000. Use only on a trusted LAN and review Windows Firewall rules."
Push-Location $BackendRoot
try {
    & $PythonExecutable @PythonPrefixArguments manage.py runserver 0.0.0.0:8000
    if ($LASTEXITCODE -ne 0) {
        throw "Django development server exited with code $LASTEXITCODE."
    }
} finally {
    Pop-Location
}
