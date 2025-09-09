<#
.SYNOPSIS
Creates a symbolic link for the PowerShell profile.

.DESCRIPTION
This script creates a symbolic link from the user's profile directory to the custom profile directory specified in the dotfiles configuration.
It handles cases where the destination already exists (either as a symlink or a directory) and ensures it runs with administrator privileges.

.NOTES
This script is intended to be run from the root of the dotfiles repository.
#>

. "$PSScriptRoot\..\setup-scripts\setup-functions.ps1"

# Variables for logging
$dateTime = Get-Date -Format "yyyyMMdd-HHmmss"
$logDir = Split-Path -Parent $PSScriptRoot
$logDir = Join-Path $logDir "logs"
$scriptName = Split-Path -Leaf $PSCommandPath
$logFile = "$logDir/$scriptName-$dateTime.txt"

# Start logging
Start-Logging -LogFilePath $logFile

if (-not (Test-IsElevated)) {
    Write-Error "This script requires Administrator privileges to enable Windows features. Please re-run from an elevated PowerShell session."
    exit 1
}

# Apply the dotfiles bootstrap variables
Write-Info "Applying dotfiles bootstrap variables..."
$bootstrapVariablesPath = Join-Path $PSScriptRoot "dotfiles-configurations\dotfiles-bootstrap-variables.json"
$DotfilesVariables = Get-Content -Path $bootstrapVariablesPath | ConvertFrom-Json
if (-not $DotfilesVariables) {
    Write-WarningMessage "No dotfiles bootstrap variables found at '$bootstrapVariablesPath'."
    Stop-Logging
    Exit 1
}

# Validate required configuration values
$requiredVars = @("CUSTOM_PROFILE_FOLDER")
$missingVars = $requiredVars | Where-Object { -not $DotfilesVariables.$_ }

if ($missingVars) {
    Write-ErrorMessage "Missing required configuration variables: $($missingVars -join ', ')"
    Stop-Logging
    Exit 1
}

# Create a symbolic link to the custom profile directory
Write-Info "Creating a symbolic link to the custom profile directory"
$customProfileDirectory = Join-Path $env:USERPROFILE $DotfilesVariables.CUSTOM_PROFILE_FOLDER
$profileDirectory = Split-Path -Parent $PROFILE

# Create a symlink to the custom profile directory if it does not exist or is not a symlink
$createSymlink = $false
if (Test-Path $customProfileDirectory) {
    $item = Get-Item $customProfileDirectory -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        Write-Info "Custom profile directory already exists as a symlink: $customProfileDirectory"
    } else {
        Write-Info "Custom profile directory exists as a normal directory."
        $userInput = Read-Host "Do you want to delete this directory and replace it with a symlink? (Y/N)"
        if ($userInput -match '^(Y|y)') {
            Write-Info "Removing directory..."
            Remove-Item $customProfileDirectory -Recurse -Force
            $createSymlink = $true
        } else {
            Write-WarningMessage "Symlink creation skipped. Directory was not removed."
        }
    }
} else {
    $createSymlink = $true
}

if ($createSymlink) {
    Write-Info "Creating symbolic link to the custom profile directory: $customProfileDirectory"
    try {
        # Try to create a symbolic link
        New-Item -ItemType SymbolicLink -Path $customProfileDirectory -Value $profileDirectory -Force -ErrorAction Stop | Out-Null
        if (Test-Path $customProfileDirectory) {
            Write-Info "Symbolic link to the custom profile directory created successfully"
        } else {
            throw "Unknown error: symlink not created"
        }
    } catch {
        Write-ErrorMessage "Failed to create a symbolic link: $($_.Exception.Message)"
        Stop-Logging
        Exit 1
    }
}

Stop-Logging
