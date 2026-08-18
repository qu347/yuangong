$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepositoryRoot = Split-Path -Parent $PSScriptRoot
$SafeRepositoryRoot = $RepositoryRoot -replace '\\', '/'
Push-Location $RepositoryRoot
try {
    $TrackedFiles = @(git -c "safe.directory=$SafeRepositoryRoot" ls-files)
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to enumerate tracked files."
    }

    $ForbiddenPatterns = @(
        '(^|/)[.]env($|[.])',
        '[.]jks$',
        '[.]keystore$',
        'key[.]properties$',
        '[.]p12$',
        '[.]pem$',
        '[.]key$',
        '(^|/)build/',
        '[.]apk$',
        '[.]aab$',
        '[.]msix$'
    )
    $ForbiddenFiles = @(
        $TrackedFiles | Where-Object {
            $Path = $_ -replace '\\', '/'
            @($ForbiddenPatterns | Where-Object { $Path -match $_ }).Count -gt 0 -and
            $Path -ne '.env.example'
        }
    )
    if ($ForbiddenFiles.Count -gt 0) {
        throw "Forbidden tracked files detected: $($ForbiddenFiles -join ', ')"
    }

    $PrivateKeyFiles = @(
        git -c "safe.directory=$SafeRepositoryRoot" grep -Il -E -- 'BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY'
    )
    if ($LASTEXITCODE -notin @(0, 1)) {
        throw "Private key header scan failed."
    }
    if ($PrivateKeyFiles.Count -gt 0) {
        throw "Private key headers detected in tracked files: $($PrivateKeyFiles -join ', ')"
    }

    Write-Host "Repository safety baseline passed."
} finally {
    Pop-Location
}
