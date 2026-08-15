$ErrorActionPreference = "Stop"

function Resolve-ProjectPython {
    param([Parameter(Mandatory = $true)][string]$BackendRoot)

    $VirtualEnvironmentPython = Join-Path $BackendRoot ".venv\Scripts\python.exe"
    if (Test-Path -LiteralPath $VirtualEnvironmentPython -PathType Leaf) {
        return [pscustomobject]@{
            FilePath = $VirtualEnvironmentPython
            PrefixArguments = @()
        }
    }

    $PyLauncher = Get-Command "py" -CommandType Application -ErrorAction SilentlyContinue
    if ($null -ne $PyLauncher) {
        & $PyLauncher.Source -3.12 --version *> $null
        if ($LASTEXITCODE -eq 0) {
            return [pscustomobject]@{
                FilePath = $PyLauncher.Source
                PrefixArguments = @("-3.12")
            }
        }
    }

    $PythonCommand = Get-Command "python" -CommandType Application -ErrorAction SilentlyContinue
    if ($null -ne $PythonCommand) {
        & $PythonCommand.Source --version *> $null
        if ($LASTEXITCODE -eq 0) {
            return [pscustomobject]@{
                FilePath = $PythonCommand.Source
                PrefixArguments = @()
            }
        }
    }

    throw "Python 3.12 was not found. Create backend/.venv, install the py launcher with Python 3.12, or add python to PATH."
}
