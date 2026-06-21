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

# Function to install the dotfiles pre-requisites
function Install-DotfilesPrerequisites {
    Write-Info "Installing dotfiles prerequisites..."
    $installModuleParams = @{}
    $allUsersScope = if (Test-IsElevated) { 'AllUsers' } else { 'CurrentUser' }
    $wingetScope    = if (Test-IsElevated) { '--scope machine' } else { '' }
    try {
        # Check if NuGet provider is installed
        if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
            Write-Info "NuGet provider is not installed. Installing now..."
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope $allUsersScope
            Import-PackageProvider -Name NuGet -Force
        } else {
            Write-Info "NuGet provider is already installed, skipping installation."
        }
    } catch {
        Write-ErrorMessage "Failed to check/install NuGet provider: $($_.Exception.Message)"
        return $false
    }

    # Check if winget is available
    try {
        $wingetAvailable = Get-Command winget -ErrorAction SilentlyContinue
        if ($wingetAvailable) {
            Write-Info "Winget is available, proceeding with installations."
        } else {
            Write-WarningMessage "Winget is not available. Some installations may not work as expected."
        }
    } catch {
        Write-ErrorMessage "Failed to check winget availability: $($_.Exception.Message)"
        return $false
    }

    # Install PowerShell if not present
    try {
        if (-not (Get-Command pwsh -ErrorAction SilentlyContinue)) {
            Write-Info "PowerShell is not installed. Installing PowerShell..."
            if ($wingetAvailable) {
                try {
                    $result = Invoke-Expression "winget install --id Microsoft.PowerShell -e $wingetScope --force --accept-source-agreements --accept-package-agreements"
                    if ($LASTEXITCODE -ne 0) { throw "Failed to install PowerShell: $result" }
                } catch {
                    Write-ErrorMessage "Error installing PowerShell: $_"
                    Write-WarningMessage "Continuing with script, but some features may not work correctly."
                }
            } else {
                Write-WarningMessage "Winget is not available. Please install PowerShell manually."
            }
        } else {
            Write-Info "PowerShell 7 is already installed, skipping installation."
        }
    } catch {
        Write-ErrorMessage "Failed to install PowerShell: $($_.Exception.Message)"
        return $false
    }

    # Ensure NuGet and PowerShellGet are up to date
    # Check and update NuGet provider
    try {
        $nugetProvider = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
        if (-not $nugetProvider -or $nugetProvider.Version -lt [Version]'2.8.5.201') {
            Write-Info "Updating NuGet provider..."
            try {
                Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope $allUsersScope -ErrorAction Stop
                Import-PackageProvider -Name NuGet -Force
            } catch {
                Write-WarningMessage "Failed to update NuGet provider: $_"
            }
        } else {
            Write-Info "NuGet provider is up to date."
        }
    } catch {
        Write-ErrorMessage "Failed to update NuGet provider: $($_.Exception.Message)"
    }

    # Check and update PowerShellGet
    try {
        $psGetModule = Get-Module -ListAvailable PowerShellGet | Sort-Object Version -Descending | Select-Object -First 1
        if (-not $psGetModule -or $psGetModule.Version -lt [Version]'2.2.5') {
            Write-Info "Updating PowerShellGet module..."
            try {
                Install-Module -Name PowerShellGet -Force -Scope $allUsersScope -ErrorAction Stop
                Write-Info "PowerShellGet updated. Please restart PowerShell to use the new version."
            } catch {
                Write-WarningMessage "Failed to update PowerShellGet: $_"
            }
        } else {
            Write-Info "PowerShellGet is up to date."
        }
    } catch {
        Write-ErrorMessage "Failed to install PowerShellGet module: $($_.Exception.Message)"
        return $false
    }

    try {
        # Determine if -AcceptLicense switch is supported
        $psGetModule = Get-Module PowerShellGet -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
        if ($psGetModule -and $psGetModule.Version -ge [Version]"2.0.0") {
            $installModuleParams.AcceptLicense = $true
        }
    } catch {
        Write-WarningMessage "Failed to check PowerShellGet version: $($_.Exception.Message)"
        $installModuleParams = @{}
    }

    # Install Git if not present
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Info "Git not found. Installing Git..."
        if ($wingetAvailable) {
            try {
                $result = Invoke-Expression "winget install --id Git.Git -e $wingetScope --force --accept-source-agreements --accept-package-agreements"
                if ($LASTEXITCODE -ne 0) { throw "Failed to install Git: $result" }
            } catch {
                Write-ErrorMessage "Error installing Git: $_"
                Write-WarningMessage "Continuing with script, but some features may not work correctly."
            }
        } else {
            Write-WarningMessage "Winget is not available. Please install Git manually."
        }
    } else {
        Write-Info "Git is already installed, skipping installation."
    }

    # Ensure the PSGallery repository is registered
    try {
        $psGallery = Get-PSRepository -Name "PSGallery" -ErrorAction Stop
        if ($psGallery -and $psGallery.InstallationPolicy -ne "Trusted") {
            Write-Info "PSGallery repository is not trusted. Setting it to Trusted..."
            Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted
        }
    } catch {
        if ($_.Exception.Message -like '*already exists*') {
            Write-Info "PSGallery repository already exists. Skipping registration."
        } else {
            Write-Info "PSGallery repository not found. Registering it now..."
            try {
                Register-PSRepository -Default -ErrorAction Stop
            } catch {
                Write-ErrorMessage "Failed to register PSGallery repository: $_"
            }
        }
    }

    # Register the default repository if not already registered
    if (-not (Get-PSRepository -Name "PSGallery" -ErrorAction SilentlyContinue)) {
        Write-Info "Registering default PowerShell repository..."
        Register-PSRepository -Default
    }

    # Install the Winget Cmdlet required for enabling Windows features and system-level installation
    Write-Info "Ensuring the Winget Cmdlet is installed..."

    # Only install the module if it isn't already installed
    if (-not (Get-Module -ListAvailable -Name Microsoft.WinGet.Configuration)) {
        Write-Info "Installing the Microsoft.WinGet.Configuration module..."
        try {
            Install-Module -Name Microsoft.WinGet.Configuration -Force -Scope $allUsersScope @installModuleParams
            Write-Info "Microsoft.WinGet.Configuration module installed."
        } catch {
            Write-WarningMessage "Failed to install Microsoft.WinGet.Configuration: $_"
        }
    } else {
        Write-Info "Microsoft.WinGet.Configuration module is already installed, skipping installation."
    }

    return $true
}

# Function to return the current user
function Get-CurrentUser {
    try {
        $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        return $currentUser
    } catch {
        Write-ErrorMessage "Failed to get current user: $($_.Exception.Message)"
        return $null
    }
}

# Function to test if this powershell script is run as an administrator
function Test-IsElevated {
    $wid = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $prp = [System.Security.Principal.WindowsPrincipal]::new($wid)
    $adm = [System.Security.Principal.WindowsBuiltInRole]::Administrator
    return $prp.IsInRole($adm)
}


# Function to check if the script is running as Administrator
function Test-RunningAsAdmin {
    return Test-IsElevated
}

# Function to check if the script is running as a normal user
function Test-RunningAsUser {
    return -not (Test-RunningAsAdmin)
}

# Function to check if the script is running as SYSTEM
function Test-RunningAsSystem {
    $wid = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    return $wid.Name -eq "NT AUTHORITY\SYSTEM"
}

# Function to check if the script is running as a service
function Test-RunningAsService {
    $wid = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    return $wid.Name -eq "NT SERVICE\TrustedInstaller"
}

# Function to check if the script is running as a user with administrative privileges
function Test-RunningAsAdminUser {
    return Test-IsElevated
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

function Get-DotfilesConfigDirectory {
    $DotfilesRoot = Split-Path -Parent $PSScriptRoot
    return (Join-Path $DotfilesRoot "dotfiles-configurations")
}

function Initialize-DotfilesConfiguration {
    param (
        [switch]$NonInteractive
    )

    $DotfilesRoot = Split-Path -Parent $PSScriptRoot
    $ConfigScript = Join-Path (Join-Path $DotfilesRoot "setup-scripts") "configure.ps1"

    if (-not (Test-Path -LiteralPath $ConfigScript)) {
        throw "Configuration script not found: $ConfigScript"
    }

    $ConfigDirectory = Get-DotfilesConfigDirectory
    $RequiredConfigFiles = @(
        "dotfiles-bootstrap-variables.json",
        "git-variables.json",
        "env-variables.json",
        "winget-packages.json"
    )

    $MissingConfigFiles = @($RequiredConfigFiles | Where-Object { -not (Test-Path -LiteralPath (Join-Path $ConfigDirectory $_)) })
    if ($MissingConfigFiles.Count -eq 0) {
        return
    }

    Write-WarningMessage "Missing local configuration files: $($MissingConfigFiles -join ', ')"
    Write-Info "Launching dotfiles configuration TUI to create local configuration from .example templates..."

    if ($NonInteractive) {
        & $ConfigScript -NonInteractive
    } else {
        & $ConfigScript
    }

    if (-not $?) {
        throw "Configuration TUI failed."
    }
}

function Resolve-DotfilesRepositoryUrl {
    param (
        [Parameter(Mandatory)]
        $DotfilesVariables
    )

    $endpointType = $DotfilesVariables.REPOSITORY_ENDPOINT_TYPE
    if ([string]::IsNullOrWhiteSpace($endpointType)) {
        $endpointType = "github-https"
    }

    switch ($endpointType) {
        "github-https" {
            return "https://github.com/$($DotfilesVariables.GITHUB_ACCOUNT)/$($DotfilesVariables.GITHUB_DOTFILES_REPO).git"
        }
        "github-ssh" {
            return "git@github.com:$($DotfilesVariables.GITHUB_ACCOUNT)/$($DotfilesVariables.GITHUB_DOTFILES_REPO).git"
        }
        "custom" {
            if ([string]::IsNullOrWhiteSpace($DotfilesVariables.CUSTOM_REPOSITORY_URL)) {
                throw "CUSTOM_REPOSITORY_URL must be set when REPOSITORY_ENDPOINT_TYPE is 'custom'."
            }
            return $DotfilesVariables.CUSTOM_REPOSITORY_URL
        }
        default {
            throw "Unsupported REPOSITORY_ENDPOINT_TYPE '$endpointType'. Supported values: github-https, github-ssh, custom."
        }
    }
}

function Sync-DotfilesLocalConfiguration {
    param (
        [Parameter(Mandatory)]
        [string]$SourceRoot,
        [Parameter(Mandatory)]
        [string]$TargetRoot
    )

    $sourceConfigDirectory = Join-Path $SourceRoot "dotfiles-configurations"
    $targetConfigDirectory = Join-Path $TargetRoot "dotfiles-configurations"

    if (-not (Test-Path -LiteralPath $sourceConfigDirectory)) { return }
    if (-not (Test-Path -LiteralPath $targetConfigDirectory)) {
        New-Item -ItemType Directory -Path $targetConfigDirectory -Force | Out-Null
    }

    $sourcePath = (Get-Item -LiteralPath $sourceConfigDirectory).FullName
    $targetPath = (Get-Item -LiteralPath $targetConfigDirectory).FullName
    if ($sourcePath -eq $targetPath) { return }

    Get-ChildItem -LiteralPath $sourceConfigDirectory -Filter "*.json" -File | ForEach-Object {
        $targetFile = Join-Path $targetConfigDirectory $_.Name
        Copy-Item -LiteralPath $_.FullName -Destination $targetFile -Force
        Write-Info "Copied local configuration '$($_.Name)' to cloned repository."
    }
}

# Function to get the dotfiles bootstrap variables
function Get-DotfilesBootstrapVariables {
    try {
        Initialize-DotfilesConfiguration

        $DotfilesConfigFolder = Get-DotfilesConfigDirectory
        $DotfilesVariablesFile = Get-ChildItem -LiteralPath $DotfilesConfigFolder -Filter "dotfiles-bootstrap-variables.json" -ErrorAction Stop

        if ($DotfilesVariablesFile) {
            $DotfilesVariables = Get-Content -LiteralPath $DotfilesVariablesFile.FullName | ConvertFrom-Json
        } else {
            throw "The dotfiles-bootstrap-variables.json file was not found in $DotfilesConfigFolder"
        }
    } catch {
        Write-Host $_.Exception.Message -ForegroundColor Red
        Write-Host "Please run setup-scripts\configure.ps1 and try again."
        Stop-Logging
        Exit 1
    }

    Write-Host "Dotfiles Bootstrap Variables to be applied:"
    foreach ($kv in $DotfilesVariables.PSObject.Properties) {
        if ($kv.Name -eq "REPOSITORY_ENDPOINTS") { continue }
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
function Test-RunningInVM {
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
