<#
.SYNOPSIS
Creates symbolic links for PowerShell profile files.

.DESCRIPTION
This script creates a symbolic link for each .ps1 file found in the dotfiles 'powershell-profiles' directory
into the user's active PowerShell profile directory ($PROFILE parent). This lets profile scripts be tracked
in git while PowerShell loads them from the expected location. If a profile file already exists as a regular
file it is left untouched to avoid data loss. This script is idempotent.

.NOTES
This script is intended to be run from the root of the dotfiles repository.
Requires Administrator privileges to create symbolic links on Windows.
#>

# dotfileRootDir is the root directory of the dotfiles repository
$dotfileRootDir = Split-Path -Parent $PSScriptRoot

. "$dotfileRootDir\setup-scripts\setup-functions.ps1"

# Variables for logging
$dateTime = Get-Date -Format "yyyyMMdd-HHmmss"
$logDir = Join-Path $dotfileRootDir "logs"
$scriptName = Split-Path -Leaf $PSCommandPath
$logFile = "$logDir/$scriptName-$dateTime.txt"

# Start logging
Start-Logging -LogFilePath $logFile

if (-not (Test-IsElevated)) {
    Write-Error "This script requires Administrator privileges to enable Windows features. Please re-run from an elevated PowerShell session."
    exit 1
}

# Symlink each profile file from the dotfiles powershell-profiles directory
# into the actual PowerShell profile directory ($profileDirectory).
# This keeps source files tracked in git while PowerShell loads them from the expected location.
Write-Info "Creating symbolic links for PowerShell profile files"
$powershellProfilesSource = Join-Path $dotfileRootDir "powershell-profiles"
$profileDirectory = Split-Path -Parent $PROFILE

if (-not (Test-Path $powershellProfilesSource)) {
    Write-ErrorMessage "Powershell profiles source directory not found: $powershellProfilesSource"
    Stop-Logging
    Exit 1
}

# Ensure the target profile directory exists (it may not on a fresh install)
if (-not (Test-Path $profileDirectory)) {
    Write-Info "Creating PowerShell profile directory: $profileDirectory"
    New-Item -ItemType Directory -Path $profileDirectory -Force | Out-Null
}

$profileFiles = Get-ChildItem -Path $powershellProfilesSource -Filter "*.ps1"
if ($profileFiles.Count -eq 0) {
    Write-WarningMessage "No .ps1 profile files found in: $powershellProfilesSource"
} else {
    foreach ($profileFile in $profileFiles) {
        $symlinkPath = Join-Path $profileDirectory $profileFile.Name

        if (Test-Path $symlinkPath) {
            $existingItem = Get-Item $symlinkPath -Force
            if ($existingItem.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                if ($existingItem.Target -eq $profileFile.FullName) {
                    Write-Info "Symlink for '$($profileFile.Name)' is already correct. Skipping."
                    continue
                } else {
                    Write-Info "Updating stale symlink for '$($profileFile.Name)'..."
                    Remove-Item $symlinkPath -Force
                }
            } else {
                Write-WarningMessage "Profile file '$($profileFile.Name)' exists as a regular file at '$symlinkPath'. Skipping to avoid data loss."
                continue
            }
        }

        Write-Info "Creating symlink: $symlinkPath -> $($profileFile.FullName)"
        try {
            New-Item -ItemType SymbolicLink -Path $symlinkPath -Value $profileFile.FullName -ErrorAction Stop | Out-Null
            Write-Info "Symlink created for '$($profileFile.Name)'."
        } catch {
            Write-ErrorMessage "Failed to create symlink for '$($profileFile.Name)': $($_.Exception.Message)"
            Stop-Logging
            Exit 1
        }
    }
}

Stop-Logging
