param(
    [ValidateSet("android", "windows", "all")][string]$Platform = "all",
    [string]$ConfigFile,
    [Parameter(Mandatory = $true)][string]$OutputDirectory,
    [switch]$ValidationOnly,
    [switch]$AllowDevelopmentPlaceholders
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "release-common.ps1")

function Stop-Safely {
    param([Parameter(Mandatory = $true)][string]$Code)
    throw "Internal release build failed: $Code."
}

function Get-ApkSigner {
    $Command = Get-Command "apksigner" -ErrorAction SilentlyContinue
    if ($null -ne $Command) {
        return $Command.Source
    }
    $AndroidSdkRoot = [Environment]::GetEnvironmentVariable("ANDROID_HOME", "Process")
    if ([string]::IsNullOrWhiteSpace($AndroidSdkRoot)) {
        $AndroidSdkRoot = [Environment]::GetEnvironmentVariable("ANDROID_SDK_ROOT", "Process")
    }
    if ([string]::IsNullOrWhiteSpace($AndroidSdkRoot)) {
        Stop-Safely "android_sdk_missing"
    }
    $BuildTools = Join-Path $AndroidSdkRoot "build-tools"
    $Candidate = Get-ChildItem -LiteralPath $BuildTools -Filter "apksigner.bat" -Recurse -File |
        Sort-Object FullName -Descending |
        Select-Object -First 1
    if ($null -eq $Candidate) {
        Stop-Safely "apksigner_missing"
    }
    return $Candidate.FullName
}

function New-RandomSecret {
    $Bytes = New-Object byte[] 32
    $Generator = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $Generator.GetBytes($Bytes)
    } finally {
        $Generator.Dispose()
    }
    return [Convert]::ToBase64String($Bytes)
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

function Set-ProcessEnvironment {
    param([hashtable]$Values, [hashtable]$OriginalValues)
    foreach ($Name in $Values.Keys) {
        if (-not $OriginalValues.ContainsKey($Name)) {
            $OriginalValues[$Name] = [Environment]::GetEnvironmentVariable($Name, "Process")
        }
        [Environment]::SetEnvironmentVariable($Name, $Values[$Name], "Process")
    }
}

function Restore-ProcessEnvironment {
    param([hashtable]$OriginalValues)
    foreach ($Name in $OriginalValues.Keys) {
        [Environment]::SetEnvironmentVariable($Name, $OriginalValues[$Name], "Process")
    }
}

$RepositoryRoot = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$FlutterRoot = Join-Path $RepositoryRoot "apps\employee_app"
$IdentityScript = Join-Path $PSScriptRoot "validate-release-identity.ps1"
$VerifierScript = Join-Path $PSScriptRoot "verify-release-artifacts.ps1"
if ([string]::IsNullOrWhiteSpace($ConfigFile)) {
    $ConfigFile = Join-Path $RepositoryRoot "config\release.validation.json"
}
$ConfigPath = [System.IO.Path]::GetFullPath($ConfigFile)
$OutputPath = [System.IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\')
$RepositoryPrefix = $RepositoryRoot + [System.IO.Path]::DirectorySeparatorChar
if ($OutputPath.StartsWith($RepositoryPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    Stop-Safely "output_inside_repository"
}
if (Test-Path -LiteralPath $OutputPath) {
    Stop-Safely "output_already_exists"
}
$OutputParent = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $OutputParent -PathType Container)) {
    [System.IO.Directory]::CreateDirectory($OutputParent) | Out-Null
}

$SafeRepositoryRoot = $RepositoryRoot -replace '\\', '/'
$GitStatus = @(git -c "safe.directory=$SafeRepositoryRoot" status --porcelain --untracked-files=all)
if ($LASTEXITCODE -ne 0) { Stop-Safely "git_status_failed" }
if ($GitStatus.Count -gt 0) { Stop-Safely "git_worktree_not_clean" }
# Contract equivalent: git rev-parse HEAD, with only a scoped safe.directory override.
$GitCommitText = git -c "safe.directory=$SafeRepositoryRoot" rev-parse HEAD
$GitCommit = $GitCommitText.Trim()
if ($LASTEXITCODE -ne 0 -or $GitCommit -notmatch '^[0-9a-f]{40}$') { Stop-Safely "git_commit_invalid" }

$IdentityArguments = @("-ConfigFile", $ConfigPath, "-AsJson")
if ($AllowDevelopmentPlaceholders) { $IdentityArguments += "-AllowDevelopmentPlaceholders" }
$IdentityJson = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $IdentityScript @IdentityArguments
if ($LASTEXITCODE -ne 0) { Stop-Safely "identity_validation_failed" }
$Identity = $IdentityJson | ConvertFrom-Json
if ($Identity.validation_only -and -not $ValidationOnly) {
    Stop-Safely "validation_identity_requires_validation_only"
}
if ($ValidationOnly -and -not $AllowDevelopmentPlaceholders -and $Identity.validation_only) {
    Stop-Safely "validation_placeholders_not_allowed"
}

$TempOutput = "$OutputPath.tmp-$([Guid]::NewGuid().ToString('N'))"
$TempSigningDirectory = $null
$EnvironmentOriginals = @{}
$Artifacts = [System.Collections.Generic.List[object]]::new()
[System.IO.Directory]::CreateDirectory($TempOutput) | Out-Null

try {
    foreach ($CacheVariable in @("GRADLE_USER_HOME", "PUB_CACHE")) {
        $ProcessValue = [Environment]::GetEnvironmentVariable($CacheVariable, "Process")
        $UserValue = [Environment]::GetEnvironmentVariable($CacheVariable, "User")
        if ([string]::IsNullOrWhiteSpace($ProcessValue) -and -not [string]::IsNullOrWhiteSpace($UserValue)) {
            Set-ProcessEnvironment -Values @{ $CacheVariable = $UserValue } -OriginalValues $EnvironmentOriginals
        }
    }
    if ($Platform -in @("android", "all")) {
        $SigningValues = @{}
        if ($ValidationOnly) {
            $Marker = New-TemporaryFile
            $TempSigningDirectory = "$($Marker.FullName).d"
            Remove-Item -LiteralPath $Marker.FullName -Force
            [System.IO.Directory]::CreateDirectory($TempSigningDirectory) | Out-Null
            $KeystorePath = Join-Path $TempSigningDirectory "validation-only.jks"
            $Password = New-RandomSecret
            $SigningValues = @{
                ANDROID_KEYSTORE_PATH = $KeystorePath
                ANDROID_KEYSTORE_PASSWORD = $Password
                ANDROID_KEY_ALIAS = "validation-only"
                ANDROID_KEY_PASSWORD = $Password
            }
            $Keytool = (Get-Command "keytool" -ErrorAction Stop).Source
            Invoke-ReleaseNativeChecked "temporary_keystore_failed" {
                & $Keytool -genkeypair -keystore $KeystorePath -storepass $Password `
                    -keypass $Password -alias "validation-only" -keyalg RSA -keysize 2048 `
                    -validity 2 -dname "CN=Validation Only, O=Non Distributable" -noprompt *> $null
            }
        } else {
            foreach ($Name in @("ANDROID_KEYSTORE_PATH", "ANDROID_KEYSTORE_PASSWORD", "ANDROID_KEY_ALIAS", "ANDROID_KEY_PASSWORD")) {
                $Value = [Environment]::GetEnvironmentVariable($Name, "Process")
                if ([string]::IsNullOrWhiteSpace($Value)) { Stop-Safely "android_signing_missing" }
                $SigningValues[$Name] = $Value
            }
        }
        Set-ProcessEnvironment -Values $SigningValues -OriginalValues $EnvironmentOriginals
        Push-Location $FlutterRoot
        try {
            Invoke-ReleaseNativeChecked "android_release_build_failed" {
                flutter build apk --release "--dart-define-from-file=$ConfigPath"
            }
        } finally {
            Pop-Location
        }
        $SourceApk = Join-Path $FlutterRoot "build\app\outputs\flutter-apk\app-release.apk"
        if (-not (Test-Path -LiteralPath $SourceApk -PathType Leaf)) { Stop-Safely "android_artifact_missing" }
        $ApkSigner = Get-ApkSigner
        $SignerOutput = @(& $ApkSigner verify --verbose --print-certs $SourceApk 2>&1)
        if ($LASTEXITCODE -ne 0) { Stop-Safely "android_signature_verification_failed" }
        $FingerprintMatch = [regex]::Match(($SignerOutput -join "`n"), '(?i)certificate SHA-256 digest:\s*([0-9a-f]{64})')
        if (-not $FingerprintMatch.Success) { Stop-Safely "android_certificate_fingerprint_missing" }
        $AndroidFilename = if ($ValidationOnly) {
            "ANDROID-NON-DISTRIBUTABLE.apk"
        } else {
            "employee-app-android-$($Identity.version)+$($Identity.build_number).apk"
        }
        $AndroidPath = Join-Path $TempOutput $AndroidFilename
        Copy-Item -LiteralPath $SourceApk -Destination $AndroidPath
        $AndroidFile = Get-Item -LiteralPath $AndroidPath
        $AndroidHash = Get-Sha256Hex -Path $AndroidPath
        $Fingerprint = $FingerprintMatch.Groups[1].Value
        $Artifacts.Add([ordered]@{
            platform = "android"
            filename = $AndroidFilename
            size = [long]$AndroidFile.Length
            sha256 = $AndroidHash
            signed = $true
            signing_identity = "sha256:$($Fingerprint.ToLowerInvariant())"
        })
    }

    if ($Platform -in @("windows", "all")) {
        $TrackFileAccessOriginal = [Environment]::GetEnvironmentVariable("TrackFileAccess", "Process")
        [Environment]::SetEnvironmentVariable("TrackFileAccess", "false", "Process")
        try {
            Push-Location $FlutterRoot
            try {
                Invoke-ReleaseNativeChecked "windows_release_build_failed" {
                    flutter build windows --release "--dart-define-from-file=$ConfigPath"
                }
            } finally {
                Pop-Location
            }
        } finally {
            [Environment]::SetEnvironmentVariable("TrackFileAccess", $TrackFileAccessOriginal, "Process")
        }
        $WindowsRelease = Join-Path $FlutterRoot "build\windows\x64\runner\Release"
        $WindowsExe = Join-Path $WindowsRelease "employee_app.exe"
        if (-not (Test-Path -LiteralPath $WindowsExe -PathType Leaf)) { Stop-Safely "windows_artifact_missing" }

        $WindowsSigningNames = @("WINDOWS_SIGNING_CERT_PFX", "WINDOWS_SIGNING_CERT_PASSWORD", "WINDOWS_TIMESTAMP_URL")
        $WindowsSigningValues = @($WindowsSigningNames | ForEach-Object { [Environment]::GetEnvironmentVariable($_, "Process") })
        $WindowsSigningPresent = @($WindowsSigningValues | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count
        if ($WindowsSigningPresent -notin @(0, $WindowsSigningNames.Count)) { Stop-Safely "windows_signing_incomplete" }
        $WindowsSigned = $false
        $WindowsIdentity = $null
        if ($WindowsSigningPresent -eq $WindowsSigningNames.Count) {
            $SignTool = (Get-Command "signtool" -ErrorAction Stop).Source
            Invoke-ReleaseNativeChecked "windows_signing_failed" {
                & $SignTool sign /fd SHA256 /td SHA256 `
                    /f $WindowsSigningValues[0] /p $WindowsSigningValues[1] `
                    /tr $WindowsSigningValues[2] $WindowsExe *> $null
            }
            $Signature = Get-AuthenticodeSignature -LiteralPath $WindowsExe
            if ($Signature.Status -ne "Valid" -or $null -eq $Signature.SignerCertificate) { Stop-Safely "windows_signature_verification_failed" }
            $Hasher = [System.Security.Cryptography.SHA256]::Create()
            try {
                $CertificateHashBytes = $Hasher.ComputeHash($Signature.SignerCertificate.RawData)
            } finally {
                $Hasher.Dispose()
            }
            $WindowsIdentity = "sha256:" + ([BitConverter]::ToString($CertificateHashBytes) -replace '-', '').ToLowerInvariant()
            $WindowsSigned = $true
        }

        $WindowsPackageDirectory = Join-Path $TempOutput "windows-package"
        Copy-Item -LiteralPath $WindowsRelease -Destination $WindowsPackageDirectory -Recurse
        $WindowsFilename = if ($WindowsSigned -and -not $ValidationOnly) {
            "employee-app-windows-$($Identity.version)+$($Identity.build_number).zip"
        } else {
            "WINDOWS-UNSIGNED-NON-DISTRIBUTABLE.zip"
        }
        $WindowsZip = Join-Path $TempOutput $WindowsFilename
        Compress-Archive -Path (Join-Path $WindowsPackageDirectory "*") -DestinationPath $WindowsZip -CompressionLevel Optimal
        Remove-Item -LiteralPath $WindowsPackageDirectory -Recurse -Force
        $WindowsFile = Get-Item -LiteralPath $WindowsZip
        $WindowsHash = Get-Sha256Hex -Path $WindowsZip
        $Artifacts.Add([ordered]@{
            platform = "windows"
            filename = $WindowsFilename
            size = [long]$WindowsFile.Length
            sha256 = $WindowsHash
            signed = $WindowsSigned
            signing_identity = $WindowsIdentity
        })
    }

    $Manifest = [ordered]@{
        schema_version = 1
        product_name = [string]$Identity.product_name
        version = [string]$Identity.version
        build_number = [int]$Identity.build_number
        git_commit = $GitCommit
        built_at = [DateTime]::UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
        validation_only = [bool]$ValidationOnly
        api_base_url_scheme = [string]$Identity.api_base_url_scheme
        artifacts = @($Artifacts)
    }
    $ManifestPath = Join-Path $TempOutput "manifest.json"
    [System.IO.File]::WriteAllText(
        $ManifestPath,
        ($Manifest | ConvertTo-Json -Depth 8),
        [System.Text.UTF8Encoding]::new($false)
    )
    $SumLines = @($Artifacts | ForEach-Object { "$($_.sha256)  $($_.filename)" })
    [System.IO.File]::WriteAllText(
        (Join-Path $TempOutput "SHA256SUMS.txt"),
        (($SumLines -join "`n") + "`n"),
        [System.Text.Encoding]::ASCII
    )
    Invoke-ReleaseNativeChecked "artifact_verification_failed" {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $VerifierScript -ManifestPath $ManifestPath
    }
    Move-Item -LiteralPath $TempOutput -Destination $OutputPath
    $TempOutput = $null
    Write-Host "Internal release validation artifacts created."
    Write-Host "Output: $OutputPath"
    exit 0
} catch {
    [Console]::Error.WriteLine("Internal release build failed safely.")
    exit 1
} finally {
    Restore-ProcessEnvironment -OriginalValues $EnvironmentOriginals
    if ($null -ne $TempSigningDirectory -and (Test-Path -LiteralPath $TempSigningDirectory)) {
        Remove-Item -LiteralPath $TempSigningDirectory -Recurse -Force
    }
    if ($null -ne $TempOutput -and (Test-Path -LiteralPath $TempOutput)) {
        Remove-Item -LiteralPath $TempOutput -Recurse -Force
    }
}
