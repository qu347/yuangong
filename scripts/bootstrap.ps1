$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepositoryRoot = Split-Path -Parent $PSScriptRoot
$BackendRoot = Join-Path $RepositoryRoot "backend"
$FlutterRoot = Join-Path $RepositoryRoot "apps\employee_app"
$ComposeFile = Join-Path $RepositoryRoot "deploy\docker-compose.dev.yml"
. (Join-Path $PSScriptRoot "python-command.ps1")

function Assert-Command {
    param([Parameter(Mandatory = $true)][string]$Name)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Missing command: $Name. Install it and add it to PATH."
    }
}

function Invoke-Checked {
    param(
        [Parameter(Mandatory = $true)][string]$Step,
        [Parameter(Mandatory = $true)][scriptblock]$Command
    )
    Write-Host "==> $Step"
    & $Command
    if ($LASTEXITCODE -ne 0) {
        throw "$Step failed with exit code $LASTEXITCODE."
    }
}

Write-Host "==> Checking Flutter, Python, and Docker"
Assert-Command "flutter"
Assert-Command "docker"
$PythonCommand = Resolve-ProjectPython -BackendRoot $BackendRoot
$PythonExecutable = $PythonCommand.FilePath
$PythonPrefixArguments = @($PythonCommand.PrefixArguments)

$EnvironmentFile = Join-Path $RepositoryRoot ".env"
if (-not (Test-Path -LiteralPath $EnvironmentFile)) {
    Write-Warning "Creating a development-only .env from .env.example. Review it before use."
    Copy-Item -LiteralPath (Join-Path $RepositoryRoot ".env.example") -Destination $EnvironmentFile
} else {
    Write-Host "==> Keeping the existing .env"
}

$VirtualEnvironment = Join-Path $BackendRoot ".venv"
if (-not (Test-Path -LiteralPath $VirtualEnvironment)) {
    Invoke-Checked "Create Python virtual environment" {
        & $PythonExecutable @PythonPrefixArguments -m venv $VirtualEnvironment
    }
}

$PythonCommand = Resolve-ProjectPython -BackendRoot $BackendRoot
$PythonExecutable = $PythonCommand.FilePath
$PythonPrefixArguments = @($PythonCommand.PrefixArguments)
Invoke-Checked "Install backend development dependencies" {
    & $PythonExecutable @PythonPrefixArguments -m pip install -r (Join-Path $BackendRoot "requirements\development.txt")
}
Invoke-Checked "Start PostgreSQL and Redis" {
    docker compose -f $ComposeFile up -d db redis
}
Invoke-Checked "Run Django migrations" {
    Push-Location $BackendRoot
    try { & $PythonExecutable @PythonPrefixArguments manage.py migrate } finally { Pop-Location }
}
Invoke-Checked "Resolve Flutter dependencies" {
    Push-Location $FlutterRoot
    try { flutter pub get } finally { Pop-Location }
}

Write-Host "==> Run baseline checks"
& (Join-Path $PSScriptRoot "check.ps1")
