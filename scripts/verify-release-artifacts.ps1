param(
    [Parameter(Mandatory = $true)][string]$ManifestPath
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Stop-Safely {
    param([Parameter(Mandatory = $true)][string]$Code)
    [Console]::Error.WriteLine("Release artifact verification failed: $Code.")
    exit 1
}

function Get-Sha256Hex {
    param([Parameter(Mandatory = $true)][string]$Path)
    $Stream = [System.IO.File]::OpenRead($Path)
    $Hasher = [System.Security.Cryptography.SHA256]::Create()
    try {
        $HashBytes = $Hasher.ComputeHash($Stream)
    } finally {
        $Hasher.Dispose()
        $Stream.Dispose()
    }
    $Hex = [BitConverter]::ToString($HashBytes) -replace '-', ''
    return $Hex.ToLowerInvariant()
}

try {
    $ResolvedManifest = [System.IO.Path]::GetFullPath($ManifestPath)
    if (-not (Test-Path -LiteralPath $ResolvedManifest -PathType Leaf)) {
        Stop-Safely "manifest_missing"
    }
    if ([System.IO.Path]::GetFileName($ResolvedManifest) -ne "manifest.json") {
        Stop-Safely "manifest_name_invalid"
    }
    $ReleaseDirectory = Split-Path -Parent $ResolvedManifest
    $SumsPath = Join-Path $ReleaseDirectory "SHA256SUMS.txt"
    if (-not (Test-Path -LiteralPath $SumsPath -PathType Leaf)) {
        Stop-Safely "checksums_missing"
    }

    $Manifest = Get-Content -LiteralPath $ResolvedManifest -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([int]$Manifest.schema_version -ne 1 -or [string]$Manifest.api_base_url_scheme -ne "https") {
        Stop-Safely "manifest_contract_invalid"
    }
    if ([string]$Manifest.git_commit -notmatch '^[0-9a-f]{40}$') {
        Stop-Safely "git_commit_invalid"
    }
    $Artifacts = @($Manifest.artifacts)
    if ($Artifacts.Count -lt 1) {
        Stop-Safely "artifacts_missing"
    }

    $ExpectedNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $ExpectedSumLines = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($Artifact in $Artifacts) {
        $Filename = [string]$Artifact.filename
        if ([string]::IsNullOrWhiteSpace($Filename) -or [System.IO.Path]::GetFileName($Filename) -ne $Filename) {
            Stop-Safely "artifact_filename_invalid"
        }
        if (-not $ExpectedNames.Add($Filename)) {
            Stop-Safely "artifact_filename_duplicate"
        }
        $ArtifactPath = Join-Path $ReleaseDirectory $Filename
        if (-not (Test-Path -LiteralPath $ArtifactPath -PathType Leaf)) {
            Stop-Safely "artifact_missing"
        }
        $File = Get-Item -LiteralPath $ArtifactPath
        if ([long]$Artifact.size -ne [long]$File.Length) {
            Stop-Safely "artifact_size_mismatch"
        }
        $ActualHash = Get-Sha256Hex -Path $ArtifactPath
        $ExpectedHashText = [string]$Artifact.sha256
        $ExpectedHash = $ExpectedHashText.ToLowerInvariant()
        if ($ExpectedHash -notmatch '^[0-9a-f]{64}$' -or $ActualHash -ne $ExpectedHash) {
            Stop-Safely "artifact_hash_mismatch"
        }
        $ExpectedSumLines.Add("$ExpectedHash  $Filename") | Out-Null
    }

    $ActualNames = @(
        Get-ChildItem -LiteralPath $ReleaseDirectory -File |
            Where-Object { $_.Name -notin @("manifest.json", "SHA256SUMS.txt") } |
            ForEach-Object { $_.Name }
    )
    if ($ActualNames.Count -ne $ExpectedNames.Count) {
        Stop-Safely "artifact_set_mismatch"
    }
    foreach ($Name in $ActualNames) {
        if (-not $ExpectedNames.Contains($Name)) {
            Stop-Safely "artifact_set_mismatch"
        }
    }

    $ActualSumLines = @(Get-Content -LiteralPath $SumsPath -Encoding ASCII | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($ActualSumLines.Count -ne $ExpectedSumLines.Count) {
        Stop-Safely "checksums_mismatch"
    }
    foreach ($Line in $ActualSumLines) {
        if (-not $ExpectedSumLines.Contains($Line)) {
            Stop-Safely "checksums_mismatch"
        }
    }

    Write-Host "Release artifacts verified: $($Artifacts.Count)."
    exit 0
} catch {
    $FailureType = $_.Exception.GetType().Name
    $FailureLine = $_.InvocationInfo.ScriptLineNumber
    Stop-Safely "unexpected_${FailureType}_line_$FailureLine"
}
