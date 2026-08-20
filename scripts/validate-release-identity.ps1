param(
    [string]$ConfigFile,
    [switch]$AllowDevelopmentPlaceholders,
    [switch]$AsJson
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Stop-Safely {
    param([Parameter(Mandatory = $true)][string]$Code)
    [Console]::Error.WriteLine("Release identity validation failed: $Code.")
    exit 1
}

try {
    $RepositoryRoot = Split-Path -Parent $PSScriptRoot
    if ([string]::IsNullOrWhiteSpace($ConfigFile)) {
        $ConfigFile = Join-Path $RepositoryRoot "config\release.validation.json"
    }
    $ConfigPath = [System.IO.Path]::GetFullPath($ConfigFile)
    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        Stop-Safely "config_missing"
    }

    $Config = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $PubspecPath = Join-Path $RepositoryRoot "apps\employee_app\pubspec.yaml"
    $GradlePath = Join-Path $RepositoryRoot "apps\employee_app\android\app\build.gradle.kts"
    $RunnerResourcePath = Join-Path $RepositoryRoot "apps\employee_app\windows\runner\Runner.rc"
    $Pubspec = Get-Content -LiteralPath $PubspecPath -Raw -Encoding UTF8
    $Gradle = Get-Content -LiteralPath $GradlePath -Raw -Encoding UTF8
    $RunnerResource = Get-Content -LiteralPath $RunnerResourcePath -Raw -Encoding UTF8

    $VersionMatch = [regex]::Match($Pubspec, '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)\s*$')
    if (-not $VersionMatch.Success) {
        Stop-Safely "version_invalid"
    }
    $Version = $VersionMatch.Groups[1].Value
    $BuildNumber = [int]$VersionMatch.Groups[2].Value
    if ($BuildNumber -lt 1) {
        Stop-Safely "build_number_invalid"
    }

    $ApplicationIdMatch = [regex]::Match($Gradle, 'applicationId\s*=\s*"([^"]+)"')
    $NamespaceMatch = [regex]::Match($Gradle, 'namespace\s*=\s*"([^"]+)"')
    $CompanyMatch = [regex]::Match($RunnerResource, 'VALUE\s+"CompanyName",\s*"([^"]+)"')
    $WindowsProductMatch = [regex]::Match($RunnerResource, 'VALUE\s+"ProductName",\s*"([^"]+)"')
    if (-not $ApplicationIdMatch.Success -or -not $NamespaceMatch.Success -or -not $CompanyMatch.Success -or -not $WindowsProductMatch.Success) {
        Stop-Safely "platform_identity_missing"
    }

    $ApiBaseUrl = [string]$Config.API_BASE_URL
    $ApiUri = $null
    if (-not [System.Uri]::TryCreate($ApiBaseUrl, [System.UriKind]::Absolute, [ref]$ApiUri) -or $ApiUri.Scheme -ne "https") {
        Stop-Safely "api_url_must_use_https"
    }
    $ProductName = [string]$Config.PRODUCT_NAME
    $SupportEmail = [string]$Config.SUPPORT_EMAIL
    if ([string]::IsNullOrWhiteSpace($ProductName) -or $SupportEmail -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') {
        Stop-Safely "release_contact_missing"
    }

    $Reasons = [System.Collections.Generic.List[string]]::new()
    if ($ApplicationIdMatch.Groups[1].Value -match '(?i)yourcompany') { $Reasons.Add("android_application_id_placeholder") }
    if ($NamespaceMatch.Groups[1].Value -match '(?i)yourcompany') { $Reasons.Add("android_namespace_placeholder") }
    if ($CompanyMatch.Groups[1].Value -match '(?i)your company|placeholder|development') { $Reasons.Add("windows_publisher_placeholder") }
    if ($ApiUri.Host -match '(?i)(^|\.)invalid$') { $Reasons.Add("api_host_placeholder") }
    if ($SupportEmail -match '(?i)@(example\.(com|test)|.*\.invalid)$') { $Reasons.Add("support_email_placeholder") }
    if ([string]$Config.APP_ENV -ne "production") { $Reasons.Add("non_production_environment") }

    if ($Reasons.Count -gt 0 -and -not $AllowDevelopmentPlaceholders) {
        Stop-Safely "development_placeholders_present"
    }

    $Result = [ordered]@{
        product_name = $ProductName
        version = $Version
        build_number = $BuildNumber
        application_id = $ApplicationIdMatch.Groups[1].Value
        namespace = $NamespaceMatch.Groups[1].Value
        windows_product_name = $WindowsProductMatch.Groups[1].Value
        api_base_url_scheme = $ApiUri.Scheme
        validation_only = ($Reasons.Count -gt 0)
        reasons = @($Reasons)
    }
    if ($AsJson) {
        $Result | ConvertTo-Json -Depth 4 -Compress
    } else {
        Write-Host "Release identity validation passed."
        Write-Host "Version: $Version+$BuildNumber"
        Write-Host "Validation only: $($Result.validation_only)"
        if ($Reasons.Count -gt 0) {
            Write-Host "Reasons: $($Reasons -join ', ')"
        }
    }
    exit 0
} catch {
    Stop-Safely "unexpected_validation_error"
}
