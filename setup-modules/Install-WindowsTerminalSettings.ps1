<#
.SYNOPSIS
Creates a symbolic link for the Windows Terminal settings.json file.

.DESCRIPTION
This script creates a symbolic link at the Windows Terminal LocalState directory,
pointing to the settings.json file tracked in this dotfiles repository. This lets
the terminal configuration be version-controlled while Windows Terminal loads it
from its conventional location.
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

$settingsSourceFile = Join-Path $dotfileRootDir "windows-terminal-settings\settings.json"
$wtPackagePath      = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe"
$wtLocalStatePath   = Join-Path $wtPackagePath "LocalState"
$symlinkPath        = Join-Path $wtLocalStatePath "settings.json"

if (-not (Test-Path $settingsSourceFile)) {
    Write-ErrorMessage "Windows Terminal settings source file not found: $settingsSourceFile"
    Stop-Logging
    Exit 1
}

if (-not (Test-Path -LiteralPath $wtPackagePath)) {
    Write-ErrorMessage "Windows Terminal package directory not found: $wtPackagePath"
    Write-ErrorMessage "Make sure Windows Terminal is installed before running this script."
    Stop-Logging
    Exit 1
}

if (-not (Test-Path -LiteralPath $wtLocalStatePath)) {
    try {
        Write-Info "Creating Windows Terminal LocalState directory: $wtLocalStatePath"
        New-Item -ItemType Directory -Path $wtLocalStatePath -Force -ErrorAction Stop | Out-Null
    } catch {
        Write-ErrorMessage "Failed to create Windows Terminal LocalState directory: $($_.Exception.Message)"
        Stop-Logging
        Exit 1
    }
}

if (Test-Path $symlinkPath) {
    $existingItem = Get-Item $symlinkPath -Force
    if ($existingItem.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        if ($existingItem.Target -eq $settingsSourceFile) {
            Write-Info "Symlink for 'settings.json' is already correct. Skipping."
            Stop-Logging
            Exit 0
        } else {
            Write-Info "Updating stale symlink for 'settings.json'..."
            Remove-Item $symlinkPath -Force
        }
    } else {
        # Back up the existing settings.json before replacing it
        $backupPath = "$symlinkPath.backup-$dateTime"
        Write-WarningMessage "'settings.json' exists as a regular file. Backing it up to: $backupPath"
        Move-Item $symlinkPath -Destination $backupPath -Force
    }
}

Write-Info "Creating symlink: $symlinkPath -> $settingsSourceFile"
try {
    New-Item -ItemType SymbolicLink -Path $symlinkPath -Value $settingsSourceFile -ErrorAction Stop | Out-Null
    Write-Info "Windows Terminal settings.json symlink created successfully."
} catch {
    Write-ErrorMessage "Failed to create symlink for 'settings.json': $($_.Exception.Message)"
    Stop-Logging
    Exit 1
}

Stop-Logging
