<#
.SYNOPSIS
    Creates an ASCII-only junction alias for the user profile directory.

.DESCRIPTION
    On Entra ID joined machines the local profile directory is created from the
    account displayName (for example 'C:\Users\AndréKakooBrioso'), which can break
    Unix-derived toolchains that do not handle non-ASCII paths well. This module
    creates a directory junction at C:\Users\<samStyleName> pointing at the real
    profile directory, where <samStyleName> is derived from the UPN prefix of the
    signed-in user (for example 'akbrioso').

    It then ensures the user-scope HOME environment variable points at the alias
    so tools that resolve '~' or '$HOME' use the ASCII-clean path. USERPROFILE is
    deliberately never modified.

    The module is idempotent: if the junction already exists with the correct
    target and HOME is already set, nothing is changed. When the real profile
    path is already ASCII-only, the whole module exits without doing anything.
#>

[CmdletBinding()]
param (
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
    $userProfile = [System.Environment]::GetEnvironmentVariable('USERPROFILE', 'Process')
    if ([string]::IsNullOrWhiteSpace($userProfile)) {
        throw 'USERPROFILE is not set; cannot derive the home alias.'
    }

    $aliasName = $null
    $isAscii = @($userProfile.ToCharArray() | Where-Object { [int]$_ -gt 127 }).Count -eq 0
    if (-not $isAscii) {
        # Prefer whoami.exe /upn because WindowsIdentity.Name is commonly domain-qualified
        # on Entra/domain joined machines rather than being a UPN.
        $windowsIdentityName = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $aliasName = Resolve-DotfilesUserHomeAliasName -WindowsIdentityName $windowsIdentityName -UserName $env:USERNAME
    }

    $currentHome = [System.Environment]::GetEnvironmentVariable('HOME', 'User')
    $preflight = Get-DotfilesUserHomeAliasPreflight `
        -UserProfile $userProfile `
        -AliasName $aliasName `
        -CurrentHome $currentHome

    switch ($preflight.Action) {
        'Skip' {
            Write-Info $preflight.Message
        }
        'Fail' {
            throw $preflight.Message
        }
        'Elevate' {
            Write-Info "Creating junction: $($preflight.AliasPath) -> $userProfile"
            New-Item -ItemType Junction -Path $preflight.AliasPath -Target $userProfile -ErrorAction Stop | Out-Null
            Write-Info 'Junction created.'
        }
        'RunNonElevated' {
            Write-Info $preflight.Message
        }
        default {
            throw "Unknown home alias preflight action '$($preflight.Action)'."
        }
    }

    if ($preflight.Action -in @('Elevate', 'RunNonElevated')) {
        if ($currentHome) {
            Write-WarningMessage "Updating existing HOME from '$currentHome' to '$($preflight.AliasPath)'."
        }
        [System.Environment]::SetEnvironmentVariable('HOME', $preflight.AliasPath, 'User')
        Write-Info "HOME set to '$($preflight.AliasPath)' in the User scope."
    }
}
catch {
    Write-ErrorMessage "Failed to configure the user home alias: $($_.Exception.Message)"
    $moduleExitCode = 1
}
finally {
    Write-Host "User home alias module log: $LogFilePath"
    Stop-Logging
}

exit $moduleExitCode
