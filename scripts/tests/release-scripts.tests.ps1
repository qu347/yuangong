$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$IdentityScript = Join-Path $RepositoryRoot "scripts\validate-release-identity.ps1"
$BuildScript = Join-Path $RepositoryRoot "scripts\build-internal-release.ps1"
$ReleaseCommonScript = Join-Path $RepositoryRoot "scripts\release-common.ps1"
$VerifierScript = Join-Path $RepositoryRoot "scripts\verify-release-artifacts.ps1"
$ValidationConfig = Join-Path $RepositoryRoot "config\release.validation.json"

function Invoke-ExpectedExit {
    param(
        [Parameter(Mandatory = $true)][int]$Code,
        [Parameter(Mandatory = $true)][scriptblock]$Command
    )
    $PreviousPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        & $Command
        $ActualCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $PreviousPreference
    }
    if ($ActualCode -ne $Code) {
        throw "Expected exit code $Code but received $ActualCode."
    }
}

if (-not (Test-Path -LiteralPath $ReleaseCommonScript -PathType Leaf)) {
    throw "Release native command helper is missing."
}
. $ReleaseCommonScript

$ResolvedUserSdk = Resolve-ReleaseAndroidSdkRoot `
    -ProcessAndroidHome "" `
    -ProcessAndroidSdkRoot "" `
    -UserAndroidHome "D:\validation-user-sdk" `
    -UserAndroidSdkRoot ""
if ($ResolvedUserSdk -ne "D:\validation-user-sdk") {
    throw "User Android SDK fallback was not selected."
}
$ResolvedProcessSdk = Resolve-ReleaseAndroidSdkRoot `
    -ProcessAndroidHome "D:\validation-process-sdk" `
    -ProcessAndroidSdkRoot "" `
    -UserAndroidHome "D:\validation-user-sdk" `
    -UserAndroidSdkRoot ""
if ($ResolvedProcessSdk -ne "D:\validation-process-sdk") {
    throw "Process Android SDK did not take precedence."
}

Invoke-ReleaseNativeChecked -Code "warning_only" -Command {
    & powershell.exe -NoProfile -Command `
        "[Console]::Error.WriteLine('expected warning'); exit 0" *> $null
}

$NativeFailureObserved = $false
try {
    Invoke-ReleaseNativeChecked -Code "expected_failure" -Command {
        & powershell.exe -NoProfile -Command "exit 9" *> $null
    }
} catch {
    $NativeFailureObserved = $true
}
if (-not $NativeFailureObserved) {
    throw "Nonzero native command exit was not rejected."
}

Invoke-ExpectedExit 1 {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $IdentityScript `
        -ConfigFile $ValidationConfig -AsJson *> $null
}

$IdentityJson = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $IdentityScript `
    -ConfigFile $ValidationConfig -AllowDevelopmentPlaceholders -AsJson
if ($LASTEXITCODE -ne 0) {
    throw "Validation identity mode failed."
}
$Identity = $IdentityJson | ConvertFrom-Json
if (-not $Identity.validation_only -or $Identity.api_base_url_scheme -ne "https") {
    throw "Validation identity result is not safely marked."
}

$TestRoot = Join-Path ([System.IO.Path]::GetTempPath()) "employee-release-script-test-$PID"
[System.IO.Directory]::CreateDirectory($TestRoot) | Out-Null
try {
    $ExistingOutput = Join-Path $TestRoot "existing-output"
    [System.IO.Directory]::CreateDirectory($ExistingOutput) | Out-Null
    $Sentinel = Join-Path $ExistingOutput "sentinel.txt"
    [System.IO.File]::WriteAllText($Sentinel, "preserve", [System.Text.Encoding]::ASCII)
    Invoke-ExpectedExit 1 {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $BuildScript `
            -Platform android -ConfigFile $ValidationConfig `
            -OutputDirectory $ExistingOutput -ValidationOnly `
            -AllowDevelopmentPlaceholders *> $null
    }
    if (-not (Test-Path -LiteralPath $Sentinel -PathType Leaf)) {
        throw "Existing release output was modified."
    }

    $ArtifactName = "ANDROID-NON-DISTRIBUTABLE.apk"
    $ArtifactPath = Join-Path $TestRoot $ArtifactName
    [System.IO.File]::WriteAllBytes($ArtifactPath, [System.Text.Encoding]::UTF8.GetBytes("artifact"))
    $Hash = (Get-FileHash -LiteralPath $ArtifactPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $Manifest = [ordered]@{
        schema_version = 1
        product_name = "Validation Product"
        version = "0.1.0"
        build_number = 1
        git_commit = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        built_at = "2026-08-19T00:00:00Z"
        validation_only = $true
        api_base_url_scheme = "https"
        artifacts = @([ordered]@{
            platform = "android"
            filename = $ArtifactName
            size = (Get-Item -LiteralPath $ArtifactPath).Length
            sha256 = $Hash
            signed = $true
            signing_identity = "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        })
    }
    [System.IO.File]::WriteAllText(
        (Join-Path $TestRoot "manifest.json"),
        ($Manifest | ConvertTo-Json -Depth 8),
        [System.Text.UTF8Encoding]::new($false)
    )
    [System.IO.File]::WriteAllText(
        (Join-Path $TestRoot "SHA256SUMS.txt"),
        "$Hash  $ArtifactName`n",
        [System.Text.Encoding]::ASCII
    )
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $VerifierScript `
        -ManifestPath (Join-Path $TestRoot "manifest.json") *> $null
    if ($LASTEXITCODE -ne 0) {
        throw "Valid release manifest did not verify."
    }

    [System.IO.File]::WriteAllBytes($ArtifactPath, [System.Text.Encoding]::UTF8.GetBytes("tampered"))
    Invoke-ExpectedExit 1 {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $VerifierScript `
            -ManifestPath (Join-Path $TestRoot "manifest.json") *> $null
    }
} finally {
    if (Test-Path -LiteralPath $TestRoot) {
        Remove-Item -LiteralPath $TestRoot -Recurse -Force
    }
}

Write-Host "Release script contract tests passed."
exit 0
