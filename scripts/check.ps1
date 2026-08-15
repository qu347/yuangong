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
        throw "Missing command: $Name. Quality checks cannot continue."
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

Assert-Command "dart"
Assert-Command "flutter"
Assert-Command "docker"
$PythonCommand = Resolve-ProjectPython -BackendRoot $BackendRoot
$PythonExecutable = $PythonCommand.FilePath
$PythonPrefixArguments = @($PythonCommand.PrefixArguments)

Push-Location $FlutterRoot
try {
    Invoke-Checked "Dart format check" { dart format --output=none --set-exit-if-changed . }
    Invoke-Checked "Flutter analyze" { flutter analyze }
    Invoke-Checked "Flutter test" { flutter test }
} finally {
    Pop-Location
}

Push-Location $BackendRoot
try {
    Invoke-Checked "Ruff format check" { & $PythonExecutable @PythonPrefixArguments -m ruff format --check --no-cache . }
    Invoke-Checked "Ruff lint" { & $PythonExecutable @PythonPrefixArguments -m ruff check --no-cache . }
    Invoke-Checked "Django check" { & $PythonExecutable @PythonPrefixArguments manage.py check }
    Invoke-Checked "pytest" { & $PythonExecutable @PythonPrefixArguments -m pytest }
} finally {
    Pop-Location
}

Invoke-Checked "Docker Compose config validation" {
    docker compose -f $ComposeFile config
}
