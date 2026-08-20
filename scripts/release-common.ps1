function Invoke-ReleaseNativeChecked {
    param(
        [Parameter(Mandatory = $true)][string]$Code,
        [Parameter(Mandatory = $true)][scriptblock]$Command
    )

    $PreviousPreference = $ErrorActionPreference
    $global:LASTEXITCODE = 9009
    try {
        $ErrorActionPreference = "Continue"
        & $Command
        $ExitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $PreviousPreference
    }
    if ($ExitCode -ne 0) {
        throw "Internal release command failed: $Code."
    }
}

function Resolve-ReleaseAndroidSdkRoot {
    param(
        [AllowEmptyString()][string]$ProcessAndroidHome = [Environment]::GetEnvironmentVariable("ANDROID_HOME", "Process"),
        [AllowEmptyString()][string]$ProcessAndroidSdkRoot = [Environment]::GetEnvironmentVariable("ANDROID_SDK_ROOT", "Process"),
        [AllowEmptyString()][string]$UserAndroidHome = [Environment]::GetEnvironmentVariable("ANDROID_HOME", "User"),
        [AllowEmptyString()][string]$UserAndroidSdkRoot = [Environment]::GetEnvironmentVariable("ANDROID_SDK_ROOT", "User")
    )

    foreach ($Candidate in @(
        $ProcessAndroidHome,
        $ProcessAndroidSdkRoot,
        $UserAndroidHome,
        $UserAndroidSdkRoot
    )) {
        if (-not [string]::IsNullOrWhiteSpace($Candidate)) {
            return $Candidate
        }
    }
    return $null
}
