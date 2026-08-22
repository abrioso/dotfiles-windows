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

. "$PSScriptRoot\..\setup-scripts\setup-functions.ps1"

$dateTime = Get-Date -Format "yyyyMMdd-HHmmss"
$logDir = Join-Path $PSScriptRoot ".." "logs"
$scriptName = Split-Path -Leaf $PSCommandPath
$logFile = "$logDir/$scriptName-$dateTime.txt"

Start-Logging -LogFilePath $logFile

try {
    $userProfile = [System.Environment]::GetEnvironmentVariable('USERPROFILE', 'Process')
    if (-not $userProfile) {
        Write-ErrorMessage "USERPROFILE is not set; cannot derive the home alias."
        Stop-Logging
        Exit 1
    }

    # Derive the alias name from the UPN prefix (e.g. akbrioso@contoso.com -> akbrioso).
    # Falls back to the current process user name when no UPN is available.
    $upn = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $aliasName = if ($upn -match '^[^@\\]+@([^@\\]+)$') {
        ($upn -split '@')[0]
    } else {
        $env:USERNAME
    }

    if (-not $aliasName) {
        Write-ErrorMessage "Could not determine a user name for the home alias."
        Stop-Logging
        Exit 1
    }

    # Nothing to do when the real profile path is already ASCII-clean.
    $isAscii = ($userProfile.ToCharArray() | Where-Object { [int]$_ -gt 127 }).Count -eq 0
    if ($isAscii) {
        Write-Info "Profile path '$userProfile' is already ASCII-only. No home alias needed."
        Stop-Logging
        Exit 0
    }

    $aliasRoot = Split-Path -Parent $userProfile
    $aliasPath = Join-Path $aliasRoot $aliasName

    if ($aliasPath -ieq $userProfile) {
        Write-WarningMessage "Alias path equals the profile path ('$aliasPath'). Skipping."
        Stop-Logging
        Exit 0
    }

    if (Test-Path -LiteralPath $aliasPath) {
        $existingItem = Get-Item -LiteralPath $aliasPath -Force
        if (-not ($existingItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            Write-WarningMessage "'$aliasPath' exists as a regular directory/file and is not a reparse point. Skipping to avoid data loss."
            Stop-Logging
            Exit 1
        }
        if ($existingItem.LinkType -ne 'Junction' -or $existingItem.Target -ne $userProfile) {
            Write-WarningMessage "'$aliasPath' exists but does not point at '$userProfile' (LinkType: $($existingItem.LinkType), Target: $($existingItem.Target)). Skipping to avoid data loss."
            Stop-Logging
            Exit 1
        }
        Write-Info "Junction '$aliasPath' already points at '$userProfile'. Skipping."
    } else {
        Write-Info "Creating junction: $aliasPath -> $userProfile"
        New-Item -ItemType Junction -Path $aliasPath -Target $userProfile -ErrorAction Stop | Out-Null
        Write-Info "Junction created."
    }

    # Point the user-scope HOME at the ASCII-clean alias. USERPROFILE is untouched.
    $currentHome = [System.Environment]::GetEnvironmentVariable('HOME', 'User')
    if ($currentHome -eq $aliasPath) {
        Write-Info "HOME is already set correctly in the User scope. Skipping."
    } else {
        if ($currentHome) {
            Write-WarningMessage "Updating existing HOME from '$currentHome' to '$aliasPath'."
        }
        [System.Environment]::SetEnvironmentVariable('HOME', $aliasPath, 'User')
        Write-Info "HOME set to '$aliasPath' in the User scope."
    }

    Exit 0
}
catch {
    Write-ErrorMessage "Failed to configure the user home alias: $($_.Exception.Message)"
    Stop-Logging
    Exit 1
}
