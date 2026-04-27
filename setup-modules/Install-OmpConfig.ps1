<#
.SYNOPSIS
Creates a symbolic link for the oh-my-posh theme configuration file.

.DESCRIPTION
This script creates the ~/.config/oh-my-posh/poshthemes/ directory (if it does not exist)
and creates a symbolic link pointing to the jandedobbeleer.omp.json theme file tracked in
this dotfiles repository. This lets the theme be version-controlled while oh-my-posh loads
it from the conventional XDG-style config location that the PowerShell profile expects.
This script is idempotent.

.NOTES
This script is intended to be run from the root of the dotfiles repository.
Creating symbolic links on Windows requires either Developer Mode to be enabled
or Administrator privileges. If neither condition is met, the script will fail.
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

# Check if Developer Mode is enabled (allows non-admin symlink creation)
$devModeKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock"
$devModeEnabled = (Get-ItemProperty -Path $devModeKey -Name "AllowDevelopmentWithoutDevLicense" -ErrorAction SilentlyContinue).AllowDevelopmentWithoutDevLicense -eq 1

if (-not $devModeEnabled -and -not (Test-IsElevated)) {
    Write-ErrorMessage "Creating symbolic links requires either Developer Mode to be enabled or Administrator privileges."
    Write-ErrorMessage "Enable Developer Mode in Settings > Privacy & Security > For Developers, or re-run as Administrator."
    Stop-Logging
    exit 1
}

if (-not $devModeEnabled) {
    Write-WarningMessage "Developer Mode is not enabled. Proceeding as Administrator."
}

$themeSourceDir = Join-Path $dotfileRootDir "poshthemes"
$themeTargetDir = Join-Path $env:USERPROFILE ".config\oh-my-posh\poshthemes"

if (-not (Test-Path $themeSourceDir)) {
    Write-ErrorMessage "Poshthemes source directory not found: $themeSourceDir"
    Stop-Logging
    Exit 1
}

# Ensure the target directory exists
if (-not (Test-Path $themeTargetDir)) {
    Write-Info "Creating oh-my-posh config directory: $themeTargetDir"
    New-Item -ItemType Directory -Path $themeTargetDir -Force | Out-Null
}

$themeFiles = Get-ChildItem -Path $themeSourceDir -Filter "*.json"
if ($themeFiles.Count -eq 0) {
    Write-WarningMessage "No .json theme files found in: $themeSourceDir"
} else {
    foreach ($themeFile in $themeFiles) {
        $symlinkPath = Join-Path $themeTargetDir $themeFile.Name

        if (Test-Path $symlinkPath) {
            $existingItem = Get-Item $symlinkPath -Force
            if ($existingItem.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                if ($existingItem.Target -eq $themeFile.FullName) {
                    Write-Info "Symlink for '$($themeFile.Name)' is already correct. Skipping."
                    continue
                } else {
                    Write-Info "Updating stale symlink for '$($themeFile.Name)'..."
                    Remove-Item $symlinkPath -Force
                }
            } else {
                Write-WarningMessage "Theme file '$($themeFile.Name)' exists as a regular file at '$symlinkPath'. Skipping to avoid data loss."
                continue
            }
        }

        Write-Info "Creating symlink: $symlinkPath -> $($themeFile.FullName)"
        try {
            New-Item -ItemType SymbolicLink -Path $symlinkPath -Value $themeFile.FullName -ErrorAction Stop | Out-Null
            Write-Info "Symlink created for '$($themeFile.Name)'."
        } catch {
            Write-ErrorMessage "Failed to create symlink for '$($themeFile.Name)': $($_.Exception.Message)"
            Stop-Logging
            Exit 1
        }
    }
}

Stop-Logging
