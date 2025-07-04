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

# Fucntion to returno the current user
function Get-CurrentUser {
    try {
        $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        return $currentUser
    } catch {
        Write-ErrorMessage "Failed to get current user: $($_.Exception.Message)"
        return $null
    }
}

# Function to elevate this powershell script to be run as an administrator
function Test-Elevated {
    $wid = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $prp = New-Object System.Security.Principal.WindowsPrincipal($wid)
    $adm = [System.Security.Principal.WindowsBuiltInRole]::Administrator
    return $prp.IsInRole($adm)
}

# Function to check if the script is running as Administrator
function Is-RunningAsAdmin {
    $wid = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $prp = New-Object System.Security.Principal.WindowsPrincipal($wid)
    $adm = [System.Security.Principal.WindowsBuiltInRole]::Administrator
    return $prp.IsInRole($adm)
}

# Function to check if the script is running as a normal user
function Is-RunningAsUser {
    return -not (Is-RunningAsAdmin)
}

# Function to check if the script is running as SYSTEM
function Is-RunningAsSystem {
    $wid = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    return $wid.Name -eq "NT AUTHORITY\SYSTEM"
}

# Function to check if the script is running as a service
function Is-RunningAsService {
    $wid = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    return $wid.Name -eq "NT SERVICE\TrustedInstaller"
}

# Function to check if the script is running as a user with administrative privileges
function Is-RunningAsAdminUser {
    $wid = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $prp = New-Object System.Security.Principal.WindowsPrincipal($wid)
    $adm = [System.Security.Principal.WindowsBuiltInRole]::Administrator
    return $prp.IsInRole($adm) -and (Is-RunningAsUser)
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

# Function to get the dotfiles bootstrap variables
function Get-DotfilesBootstrapVariables {
    try {
        $DotfilesRoot = Split-Path -Parent $PSScriptRoot
        $DotfilesConfigFolder = Join-Path $DotfilesRoot "dotfiles-configurations"
        $DotfilesVariablesFile = Get-ChildItem -Path $DotfilesConfigFolder -Filter "dotfiles-bootstrap-variables.json" -ErrorAction Stop

        if ($DotfilesVariablesFile) {
            $DotfilesVariables = Get-Content -Path $DotfilesVariablesFile.FullName | ConvertFrom-Json
        } else {
            throw "The dotfiles-bootstrap-variables.json file was not found in $DotfilesConfigFolder"
        }
    } catch {
        Write-Host $_.Exception.Message -ForegroundColor Red
        Write-Host "Please make sure that the file exists and try again."
        Stop-Logging
        Exit 1
    }

    Write-Host "Dotfiles Bootstrap Variables to be applied:"
    foreach ($kv in $DotfilesVariables.PSObject.Properties) {
        if ($kv.Value -is [System.Collections.IEnumerable] -and $kv.Value -isnot [string]) {
            Write-Host ("{0,-25}:" -f $kv.Name)
            foreach ($item in $kv.Value) {
                Write-Host ("  - {0}" -f $item)
            }
        } else {
            Write-Host ("{0,-25}: {1}" -f $kv.Name, $kv.Value)
        }
    }
    return $DotfilesVariables
}

# Function to check if script is running in a VM environment
function Is-RunningInVM {
    $vmTypes = @("VirtualBox", "VMware", "Hyper-V", "Parallels", "QEMU")
    $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem
    Write-Host "Checking if the machine is running in a VM environment..."
    foreach ($vmType in $vmTypes) {
        if ($computerSystem | Where-Object { $_.Manufacturer -like "*$vmType*" }) {
            return $true
        }
    }
    if ($computerSystem | Where-Object { $_.Model -like "*Virtual Machine*" }) {
        return $true
    }
    Write-Host "This machine is not running in a recognized VM environment."
    return $false
}
