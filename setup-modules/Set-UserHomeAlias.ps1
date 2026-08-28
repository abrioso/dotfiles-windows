<#
.SYNOPSIS
    Creates an ASCII-only junction alias for an explicitly supplied user profile.

.DESCRIPTION
    This elevated child performs only the machine-level junction mutation. The
    non-elevated setup parent resolves the original signed-in user, preflights the
    alias, passes both paths explicitly, and owns the user-scope HOME update.
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string]$UserProfile,
    [Parameter(Mandatory)]
    [string]$AliasPath,
    [string]$LogFilePath
)

. "$PSScriptRoot\..\setup-scripts\setup-functions.ps1"

if ([string]::IsNullOrWhiteSpace($LogFilePath)) {
    $moduleLogName = "{0}-{1}-{2}.txt" -f (Split-Path -Leaf $PSCommandPath), (Get-Date -Format 'yyyyMMdd-HHmmssfff'), [System.Guid]::NewGuid().ToString('N').Substring(0, 8)
    $LogFilePath = Join-Path (Join-Path $PSScriptRoot '..') "logs/$moduleLogName"
}
$LogFilePath = Start-Logging -LogFilePath $LogFilePath -PassThru -RequireRequestedPath
$moduleExitCode = 0

try {
    $preflight = Get-DotfilesUserHomeAliasJunctionPreflight `
        -UserProfile $UserProfile `
        -AliasPath $AliasPath

    switch ($preflight.Action) {
        'Elevate' {
            Write-Info "Creating junction: $AliasPath -> $UserProfile"
            New-Item -ItemType Junction -Path $AliasPath -Target $UserProfile -ErrorAction Stop | Out-Null
            Write-Info 'Junction created.'
        }
        'Skip' {
            Write-Info $preflight.Message
        }
        'Fail' {
            throw $preflight.Message
        }
        default {
            throw "Unexpected junction-only preflight action '$($preflight.Action)'."
        }
    }
}
catch {
    Write-ErrorMessage "Failed to create the user home alias junction: $($_.Exception.Message)"
    $moduleExitCode = 1
}
finally {
    Write-Host "User home alias module log: $LogFilePath"
    Stop-Logging
}

exit $moduleExitCode
