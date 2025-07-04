# setup-functions.ps1
# Shared PowerShell functions for setup scripts

<#
.SYNOPSIS
    This script contains reusable functions for setup scripts.
.DESCRIPTION
    Import this script in your setup scripts to use the shared functions.
#>

# Example: Import-Module "$PSScriptRoot\setup-functions.ps1"

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

# Function to elevate this powershell script to be run as an administrator
function Test-Elevated {
    $wid = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $prp = New-Object System.Security.Principal.WindowsPrincipal($wid)
    $adm = [System.Security.Principal.WindowsBuiltInRole]::Administrator
    return $prp.IsInRole($adm)
}

# Function to Enable Developer Mode
# This function will attempt to enable Developer Mode by modifying the registry.
function Enable-DeveloperMode {
    Write-Host "Enabling Developer Mode (requires elevation)..."
    $command = 'reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" /t REG_DWORD /f /v "AllowDevelopmentWithoutDevLicense" /d "1"'
    Start-Process powershell -ArgumentList "-NoProfile -WindowStyle Hidden -Command $command" -Verb RunAs -Wait
    Write-Host "Developer Mode should now be enabled. Please re-run this script if you still see errors."
}

# Check if Developer Mode is enabled
function Test-DeveloperMode {
    try {
        $reg = Get-ItemProperty -Path "HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\AppModelUnlock" -Name "AllowDevelopmentWithoutDevLicense" -ErrorAction Stop
        return $reg.AllowDevelopmentWithoutDevLicense -eq 1
    } catch {
        return $false
    }
}

