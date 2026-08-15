$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ScriptsRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $ScriptsRoot "python-command.ps1")

function Assert-Equal {
    param(
        [Parameter(Mandatory = $true)]$Expected,
        [Parameter(Mandatory = $true)]$Actual,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if ($Expected -ne $Actual) {
        throw "$Message Expected '$Expected', got '$Actual'."
    }
}

$SystemTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$TestRoot = Join-Path $SystemTemp ("employee-python-command-" + [guid]::NewGuid())
$OriginalPath = $env:Path
$OriginalPathExt = $env:PATHEXT

New-Item -ItemType Directory -Path $TestRoot | Out-Null

try {
    $BackendWithVenv = Join-Path $TestRoot "backend-with-venv"
    $VenvScripts = Join-Path $BackendWithVenv ".venv\Scripts"
    New-Item -ItemType Directory -Path $VenvScripts | Out-Null
    $VenvPython = Join-Path $VenvScripts "python.exe"
    New-Item -ItemType File -Path $VenvPython | Out-Null

    $env:Path = $TestRoot
    $VenvResult = Resolve-ProjectPython -BackendRoot $BackendWithVenv
    Assert-Equal $VenvPython $VenvResult.FilePath "Virtual environment must take precedence."
    Assert-Equal 0 $VenvResult.PrefixArguments.Count "Venv Python must not add prefix arguments."

    $LauncherDirectory = Join-Path $TestRoot "launcher"
    New-Item -ItemType Directory -Path $LauncherDirectory | Out-Null
    Set-Content -LiteralPath (Join-Path $LauncherDirectory "py.cmd") -Value "@exit /b 0" -Encoding Ascii
    Set-Content -LiteralPath (Join-Path $LauncherDirectory "python.cmd") -Value "@exit /b 0" -Encoding Ascii

    $env:PATHEXT = ".CMD;.EXE"
    $env:Path = $LauncherDirectory
    $PyResult = Resolve-ProjectPython -BackendRoot (Join-Path $TestRoot "backend-without-venv")
    Assert-Equal "py.cmd" (Split-Path -Leaf $PyResult.FilePath) "py launcher must precede python."
    Assert-Equal "-3.12" $PyResult.PrefixArguments[0] "py launcher must request Python 3.12."

    $PythonDirectory = Join-Path $TestRoot "python-only"
    New-Item -ItemType Directory -Path $PythonDirectory | Out-Null
    Set-Content -LiteralPath (Join-Path $PythonDirectory "python.cmd") -Value "@exit /b 0" -Encoding Ascii

    $env:Path = $PythonDirectory
    $PythonResult = Resolve-ProjectPython -BackendRoot (Join-Path $TestRoot "another-backend")
    Assert-Equal "python.cmd" (Split-Path -Leaf $PythonResult.FilePath) "python must be the final fallback."
    Assert-Equal 0 $PythonResult.PrefixArguments.Count "python fallback must not add prefix arguments."

    Write-Output "PASS: Python command precedence is venv, py -3.12, then python."
} finally {
    $env:Path = $OriginalPath
    $env:PATHEXT = $OriginalPathExt
    $ResolvedTestRoot = [System.IO.Path]::GetFullPath($TestRoot)
    if ($ResolvedTestRoot.StartsWith($SystemTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $ResolvedTestRoot -Recurse -Force
    }
}
