$ErrorActionPreference = "Stop"

function Invoke-FlutterAnalyzeAtPath {
    param([Parameter(Mandatory = $true)][string]$FlutterRoot)

    Push-Location $FlutterRoot
    try {
        & flutter analyze
        if ($LASTEXITCODE -ne 0) {
            throw "Flutter analyze failed with exit code $LASTEXITCODE."
        }
    } finally {
        Pop-Location
    }
}

function Invoke-ProjectFlutterAnalyze {
    param([Parameter(Mandatory = $true)][string]$RepositoryRoot)

    $ResolvedRepositoryRoot = [System.IO.Path]::GetFullPath($RepositoryRoot).TrimEnd("\")
    $FlutterRelativePath = "apps\employee_app"
    $FlutterRoot = Join-Path $ResolvedRepositoryRoot $FlutterRelativePath

    if ($ResolvedRepositoryRoot -notmatch "[^\x00-\x7F]") {
        Invoke-FlutterAnalyzeAtPath -FlutterRoot $FlutterRoot
        return
    }

    $SystemTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd("\")
    if ($SystemTemp -match "[^\x00-\x7F]") {
        throw "Flutter analyze requires an ASCII temporary path because Flutter 3.47 miscalculates LSP Content-Length for non-ASCII workspace names."
    }

    $JunctionPath = Join-Path $SystemTemp (
        "employee-management-flutter-analyze-" + [guid]::NewGuid().ToString("N")
    )

    if (Test-Path -LiteralPath $JunctionPath) {
        throw "Refusing to overwrite an existing temporary analysis path."
    }

    try {
        $Junction = New-Item -ItemType Junction -Path $JunctionPath -Target $ResolvedRepositoryRoot
        $JunctionTarget = [System.IO.Path]::GetFullPath([string]$Junction.Target).TrimEnd("\")
        if ($JunctionTarget -ne $ResolvedRepositoryRoot) {
            throw "Temporary analysis junction target does not match the repository."
        }

        Write-Host "==> Using a temporary ASCII junction for Flutter 3.47 analysis"
        Invoke-FlutterAnalyzeAtPath -FlutterRoot (Join-Path $JunctionPath $FlutterRelativePath)
    } finally {
        $ResolvedJunctionPath = [System.IO.Path]::GetFullPath($JunctionPath)
        $IsInsideTemp = $ResolvedJunctionPath.StartsWith(
            $SystemTemp + "\",
            [System.StringComparison]::OrdinalIgnoreCase
        )

        if ($IsInsideTemp -and (Test-Path -LiteralPath $ResolvedJunctionPath)) {
            $Junction = Get-Item -LiteralPath $ResolvedJunctionPath -Force
            $IsReparsePoint = [bool](
                $Junction.Attributes -band [System.IO.FileAttributes]::ReparsePoint
            )
            $JunctionTarget = [System.IO.Path]::GetFullPath([string]$Junction.Target).TrimEnd("\")

            if (-not $IsReparsePoint -or $JunctionTarget -ne $ResolvedRepositoryRoot) {
                throw "Refusing to remove an unverified temporary analysis path."
            }

            [System.IO.Directory]::Delete($ResolvedJunctionPath, $false)
        }
    }
}
