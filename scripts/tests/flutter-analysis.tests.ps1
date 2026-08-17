$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ScriptsRoot = Split-Path -Parent $PSScriptRoot

function Assert-True {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

$SystemTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd("\")
$TestRoot = Join-Path $SystemTemp ("employee-flutter-analysis-test-" + [guid]::NewGuid())
$RepositoryRoot = Join-Path $TestRoot "中文仓库"
$FlutterRoot = Join-Path $RepositoryRoot "apps\employee_app"
$FakeBin = Join-Path $TestRoot "fake-bin"
$ObservedPathFile = Join-Path $TestRoot "observed-path.txt"
$OriginalPath = $env:Path
$OriginalPathExt = $env:PATHEXT
$OriginalOutputPath = $env:EMPLOYEE_FLUTTER_TEST_OUTPUT

New-Item -ItemType Directory -Path $FlutterRoot -Force | Out-Null
New-Item -ItemType Directory -Path $FakeBin -Force | Out-Null
Set-Content -LiteralPath (Join-Path $FakeBin "flutter.cmd") -Encoding Ascii -Value @(
    "@echo %CD%>%EMPLOYEE_FLUTTER_TEST_OUTPUT%"
    "@exit /b 0"
)

try {
    $env:PATHEXT = ".CMD;.EXE"
    $env:Path = "$FakeBin;$OriginalPath"
    $env:EMPLOYEE_FLUTTER_TEST_OUTPUT = $ObservedPathFile

    . (Join-Path $ScriptsRoot "flutter-analysis.ps1")
    Invoke-ProjectFlutterAnalyze -RepositoryRoot $RepositoryRoot

    $ObservedPath = (Get-Content -Raw -LiteralPath $ObservedPathFile).Trim()
    Assert-True ($ObservedPath -notmatch "[^\x00-\x7F]") "Flutter analyze must run through an ASCII path."

    $ObservedRepositoryRoot = Split-Path -Parent (Split-Path -Parent $ObservedPath)
    Assert-True (-not (Test-Path -LiteralPath $ObservedRepositoryRoot)) "Temporary junction must be removed."
    Assert-True (Test-Path -LiteralPath $RepositoryRoot) "The real repository target must remain."

    Write-Output "PASS: Flutter analyze uses and removes a temporary ASCII junction."
} finally {
    $env:Path = $OriginalPath
    $env:PATHEXT = $OriginalPathExt
    $env:EMPLOYEE_FLUTTER_TEST_OUTPUT = $OriginalOutputPath

    $ResolvedTestRoot = [System.IO.Path]::GetFullPath($TestRoot)
    if ($ResolvedTestRoot.StartsWith($SystemTemp + "\", [System.StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $ResolvedTestRoot -Recurse -Force
    }
}
