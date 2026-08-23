<#
.SYNOPSIS
    Generates the Windows Terminal settings.json in its LocalState directory from
    the tracked baseline template.

.DESCRIPTION
    This script copies the baseline template from dotfiles-configurations/windows-terminal-settings.json.example
    directly into the Windows Terminal LocalState directory as settings.json. The file is generated,
    not linked: Windows Terminal owns it afterwards, and machine-specific edits (for example WSL or
    Ubuntu profiles) are made by Terminal itself in place without ever touching versioned files.

    On first run (no existing settings.json) the baseline is copied. On later runs the existing
    settings.json is left untouched so local customizations are preserved; a timestamped backup is
    never needed because the module never overwrites an existing configuration.

    To adopt new baseline defaults, delete the generated settings.json and re-run setup, or copy
    the template manually. The template remains the single source of truth for shared defaults.

    This script is idempotent and does not require elevation: the LocalState directory lives under
    the current user's LOCALAPPDATA.
#>

# dotfileRootDir is the root directory of the dotfiles repository
$dotfileRootDir = Split-Path -Parent $PSScriptRoot

. "$dotfileRootDir\setup-scripts\setup-functions.ps1"

# Variables for logging
$dateTime = Get-Date -Format "yyyyMMdd-HHmmss"
$logDir = Join-Path $dotfileRootDir "logs"
$scriptName = Split-Path -Leaf $PSCommandPath
$logFile = "$logDir/$scriptName-$dateTime.txt"

Start-Logging -LogFilePath $logFile

$templateFile = Join-Path $dotfileRootDir "dotfiles-configurations\windows-terminal-settings.json.example"
$wtPackagePath    = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe"
$wtLocalStatePath = Join-Path $wtPackagePath "LocalState"
$targetFile       = Join-Path $wtLocalStatePath "settings.json"

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

if (Test-Path -LiteralPath $targetFile) {
    # Never overwrite: Terminal-owned settings may hold machine-specific profiles.
    Write-Info "'settings.json' already exists. Preserving machine-specific configuration: $targetFile"
    Stop-Logging
    Exit 0
}

Write-Info "Generating Windows Terminal settings.json from baseline template: $targetFile"
try {
    Copy-Item -LiteralPath $templateFile -Destination $targetFile -ErrorAction Stop
    Write-Info "Windows Terminal settings.json generated successfully."
}
catch {
    Write-ErrorMessage "Failed to generate 'settings.json': $($_.Exception.Message)"
    Stop-Logging
    Exit 1
}

Stop-Logging
