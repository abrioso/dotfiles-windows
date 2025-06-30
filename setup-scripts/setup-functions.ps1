# setup-functions.ps1
# Shared PowerShell functions for setup scripts

<#
.SYNOPSIS
    This script contains reusable functions for setup scripts.
.DESCRIPTION
    Import this script in your setup scripts to use the shared functions.
#>

# Example: Import-Module "$PSScriptRoot\setup-functions.ps1"

# region Utility Functions

function Write-Info {
    param (
        [Parameter(Mandatory)]
        [string]$Message
    )
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-WarningMessage {
    param (
        [Parameter(Mandatory)]
        [string]$Message
    )
    Write-Host "[WARNING] $Message" -ForegroundColor Yellow
}

function Write-ErrorMessage {
    param (
        [Parameter(Mandatory)]
        [string]$Message
    )
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

function Start-Logging {
    param (
        [Parameter(Mandatory)]
        [string]$LogFilePath
    )
    # Ensure the log directory exists
    $logDir = Split-Path -Parent $LogFilePath
    if (!(Test-Path -Path $logDir)) { 
        try {
            New-Item -Path $logDir -ItemType Directory | Out-Null
        }
        catch {
            Write-WarningMessage "Cannot create log directory: $($_.Exception.Message)"
            $LogFilePath = "$env:TEMP\$(Split-Path -Leaf $LogFilePath)"
            Write-WarningMessage "Logging to temporary location: $LogFilePath"
        }
    }
    # Start logging to the specified file
    try {
        Start-Transcript -Path $LogFilePath -ErrorAction Stop
    }
    catch {
        Write-WarningMessage "Cannot start transcript: $($_.Exception.Message)"
    }
}        
 
function Stop-Logging {
    try {
        Stop-Transcript -ErrorAction Stop
    }
    catch {
        Write-WarningMessage "Cannot stop transcript: $($_.Exception.Message)"
    }
}

# endregion

# region Add more shared functions below

# endregion