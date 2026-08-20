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
