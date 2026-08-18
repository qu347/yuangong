$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepositoryRoot = Split-Path -Parent $PSScriptRoot
$BackendRoot = Join-Path $RepositoryRoot "backend"
$FlutterRoot = Join-Path $RepositoryRoot "apps\employee_app"
$ComposeFile = Join-Path $RepositoryRoot "deploy\docker-compose.dev.yml"
$RepositorySafetyScript = Join-Path $PSScriptRoot "repository-safety.ps1"
$SchemaFile = Join-Path ([System.IO.Path]::GetTempPath()) "employee-management-openapi-$PID.yaml"
. (Join-Path $PSScriptRoot "python-command.ps1")
. (Join-Path $PSScriptRoot "flutter-analysis.ps1")

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
    Invoke-Checked "Flutter analyze" {
        Invoke-ProjectFlutterAnalyze -RepositoryRoot $RepositoryRoot
    }
    Invoke-Checked "Flutter test" { flutter test }
} finally {
    Pop-Location
}

Push-Location $BackendRoot
try {
    Invoke-Checked "Ruff format check" { & $PythonExecutable @PythonPrefixArguments -m ruff format --check --no-cache . }
    Invoke-Checked "Ruff lint" { & $PythonExecutable @PythonPrefixArguments -m ruff check --no-cache . }
    Invoke-Checked "Django check" { & $PythonExecutable @PythonPrefixArguments manage.py check --settings=config.settings.test }
    Invoke-Checked "Migration drift check" {
        & $PythonExecutable @PythonPrefixArguments manage.py makemigrations --check --dry-run --settings=config.settings.test
    }
    Invoke-Checked "SQLite pytest" { & $PythonExecutable @PythonPrefixArguments -m pytest -q }
    Invoke-Checked "Strict OpenAPI validation" {
        & $PythonExecutable @PythonPrefixArguments manage.py spectacular --validate --fail-on-warn --settings=config.settings.test --file $SchemaFile
    }
} finally {
    Pop-Location
    if (Test-Path -LiteralPath $SchemaFile -PathType Leaf) {
        Remove-Item -LiteralPath $SchemaFile -Force
    }
}

Invoke-Checked "Docker Compose config validation" {
    docker compose -f $ComposeFile config --quiet
}

Invoke-Checked "Redis health probe" {
    docker compose -f $ComposeFile exec -T redis redis-cli ping
}

Invoke-Checked "PostgreSQL pytest" {
    docker compose -f $ComposeFile run --rm -T --no-deps `
        -v "${RepositoryRoot}\.github:/app/.github:ro" `
        -v "${RepositoryRoot}\scripts:/app/scripts:ro" `
        -v "${RepositoryRoot}\deploy:/app/deploy:ro" `
        -e DJANGO_SETTINGS_MODULE=config.settings.test `
        -e TEST_DATABASE_ENGINE=postgresql `
        -e EXPECTED_DATABASE_VENDOR=postgresql `
        -e TEST_CACHE_ENGINE=redis `
        -e REDIS_URL=redis://redis:6379/15 `
        api python -m pytest -q
}

Invoke-Checked "Repository safety baseline" {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $RepositorySafetyScript
}
