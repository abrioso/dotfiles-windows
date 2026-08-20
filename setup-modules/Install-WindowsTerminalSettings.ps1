<#
.SYNOPSIS
    Creates a local Windows Terminal settings.json from the tracked baseline template and
    creates a symbolic link for it in the Windows Terminal LocalState directory.

.DESCRIPTION
    This script uses the baseline template in dotfiles-configurations/windows-terminal-settings.json.example
    as the starting point for the local settings.json. It keeps the local settings.json out of version
    control by placing it in dotfiles-configurations/, where it is ignored by the existing .gitignore rule
    for machine-local JSON files.

    If the local settings.json does not exist, it is created from the template. If it already exists,
    it is left untouched so machine-specific changes (for example WSL or Ubuntu profiles) are preserved.

    Finally, the script creates a symbolic link at the Windows Terminal LocalState directory so the
    terminal loads the local configuration from its conventional location.

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

# Local configuration lives here, outside version control
$settingsSourceFile = Join-Path $dotfileRootDir "dotfiles-configurations\windows-terminal-settings.json"
$templateFile = Join-Path $dotfileRootDir "dotfiles-configurations\windows-terminal-settings.json.example"
$wtPackagePath      = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe"
$wtLocalStatePath   = Join-Path $wtPackagePath "LocalState"
$symlinkPath        = Join-Path $wtLocalStatePath "settings.json"

if (-not (Test-Path -LiteralPath $templateFile)) {
    Write-ErrorMessage "Windows Terminal baseline template not found: $templateFile"
    Stop-Logging
    Exit 1
}

# Validate the template is usable JSON before touching anything on disk
try {
    $templateContent = Get-Content -LiteralPath $templateFile -Raw
    $null = $templateContent | ConvertFrom-Json -ErrorAction Stop
}
catch {
    Write-ErrorMessage "Windows Terminal baseline template is not valid JSON: $templateFile. $($_.Exception.Message)"
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
    }
    catch {
        Write-ErrorMessage "Failed to create Windows Terminal LocalState directory: $($_.Exception.Message)"
        Stop-Logging
        Exit 1
    }
}

# Create the local settings.json from the template if it does not already exist.
# Machine-specific changes are intentionally preserved, so this module does not overwrite
# an existing settings.json. It only bootstraps the initial file from the shared baseline.
if (-not (Test-Path -LiteralPath $settingsSourceFile)) {
    try {
        Write-Info "Creating local Windows Terminal settings from baseline template: $settingsSourceFile"
        Copy-Item -LiteralPath $templateFile -Destination $settingsSourceFile -Force
    }
    catch {
        Write-ErrorMessage "Failed to create local settings.json: $($_.Exception.Message)"
        Stop-Logging
        Exit 1
    }
}
else {
    Write-Info "Local Windows Terminal settings already exist. Preserving machine-specific configuration: $settingsSourceFile"
}

if (Test-Path $symlinkPath) {
    $existingItem = Get-Item $symlinkPath -Force
    if ($existingItem.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        if ($existingItem.Target -eq $settingsSourceFile) {
            Write-Info "Symlink for 'settings.json' is already correct. Skipping."
            Stop-Logging
            Exit 0
        }
        else {
            Write-Info "Updating stale symlink for 'settings.json'..."
            Remove-Item $symlinkPath -Force
        }
    }
    else {
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
}
catch {
    Write-ErrorMessage "Failed to create symlink for 'settings.json': $($_.Exception.Message)"
    Stop-Logging
    Exit 1
}

Stop-Logging
