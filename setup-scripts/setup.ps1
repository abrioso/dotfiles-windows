<#
.SYNOPSIS
Main bootstrap script.

.DESCRIPTION
This script installs the pre-requisites and starts the other setup scripts with Powershell 7 
It also creates a symbolic link to the custom profile directory and clones the dotfiles repository

.NOTES
To make this work, you need to set your execution policy to unrestricted (or at least bypass) by running Set-ExecutionPolicy Unrestricted -Scope CurrentUser from a PowerShell.

#>



# Variables for logging
$dateTime = Get-Date -Format "yyyyMMdd-HHmmss"
$logDir = Split-Path -Parent $PSScriptRoot
$logDir = Join-Path $logDir "logs"
$scriptName = Split-Path -Leaf $PSCommandPath
$logFile = "$logDir/$scriptName-$dateTime.txt"

# Create the log directory if it doesn't exist
if (!(Test-Path -Path $logDir)) {
    try {
        New-Item -Path $logDir -ItemType Directory | Out-Null
    }
    catch {
        Write-Warning "Cannot create log directory: $($_.Exception.Message)"
        $logFile = "$env:TEMP\$scriptName-$dateTime.txt"
        Write-Warning "Logging to temporary location: $logFile"
    }
}

# Start logging
try {
    Start-Transcript -Path $logFile -ErrorAction Stop
}
catch {
    Write-Warning "Cannot start transcript: $($_.Exception.Message)"
}

# Check execution policy at script start
$currentPolicy = Get-ExecutionPolicy
Write-Host "Current execution policy: $currentPolicy"
if ($currentPolicy -in @("Restricted", "AllSigned")) {
    Write-Warning "Current execution policy may prevent script execution"
    Write-Warning "Consider running: Set-ExecutionPolicy RemoteSigned -Scope CurrentUser or Set-ExecutionPolicy Unrestricted -Scope CurrentUser"
}

Write-Host "Installing the pre-requisites for the dotfiles setup"

# Ensure NuGet and PowerShellGet are up to date and set AcceptLicense switch if supported
try {
    Write-Host "Ensuring NuGet and PowerShellGet are up to date..."
    Install-PackageProvider -Name NuGet -Force -Scope CurrentUser -ErrorAction SilentlyContinue
    Install-Module -Name PowerShellGet -Force -Scope CurrentUser -ErrorAction SilentlyContinue
    Import-Module PowerShellGet -Force -ErrorAction SilentlyContinue
} catch {
    Write-Warning "Could not update NuGet or PowerShellGet: $_"
}

# Determine if -AcceptLicense is supported
$psGetVersion = (Get-Module PowerShellGet -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1).Version
if ($psGetVersion -ge [Version]"2.0.0") {
    $AcceptLicenseSwitch = '-AcceptLicense'
} else {
    $AcceptLicenseSwitch = ''
}


# Install PowerShell if not present
if (-not (Get-Command pwsh -ErrorAction SilentlyContinue)) {
    Write-Host "Installing PowerShell"
    try {
        $result = winget install --id Microsoft.PowerShell -e --force --accept-source-agreements --accept-package-agreements
        if ($LASTEXITCODE -ne 0) { throw "Failed to install PowerShell: " + $result }
    } catch {
        Write-Host "Error installing PowerShell: $_" -ForegroundColor Red
        Write-Host "Continuing with script, but some features may not work correctly."
    }
} else {
    Write-Host "PowerShell 7 is already installed, skipping installation."
}

# Install Git if not present
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "Installing Git"
    try {
        $result = winget install --id Git.Git -e --force --accept-source-agreements --accept-package-agreements
        if ($LASTEXITCODE -ne 0) { throw "Failed to install Git: " + $result }
    } catch {
        Write-Host "Error installing Git: $_" -ForegroundColor Red
        Write-Host "Continuing with script, but some features may not work correctly."
    }
} else {
    Write-Host "Git is already installed, skipping installation."
}

# Check if NuGet provider is installed
if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
    Write-Host "NuGet provider is not installed. Installing now..."
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser
    Import-PackageProvider -Name NuGet -Force
}

# Register the default repository if not already registered
if (-not (Get-PSRepository -Name "PSGallery" -ErrorAction SilentlyContinue)) {
    Write-Host "Registering default PowerShell repository..."
    Register-PSRepository -Default
}

# Install the Winget Cmdlet required for enabling Windows features and system-level installation
Write-Host "Installing the Winget Cmdlet"
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted

# Check if the module is already installed
if (Get-Module -ListAvailable -Name Microsoft.WinGet.Configuration) {
    Write-Host "Uninstalling the existing Microsoft.WinGet.Configuration module..."
    Uninstall-Module -Name Microsoft.WinGet.Configuration -AllVersions -Force -Scope CurrentUser
}

Write-Host "Installing the Microsoft.WinGet.Configuration module..."
# Use AcceptLicense switch if available
if ($AcceptLicenseSwitch) {
    Install-Module -Name Microsoft.WinGet.Configuration -Force -Scope CurrentUser @($AcceptLicenseSwitch)
} else {
    Install-Module -Name Microsoft.WinGet.Configuration -Force -Scope CurrentUser
}

# Update the system PATH variable properly
try {
    # Refresh PATH from both Machine and User environment
    # Add the machine path to the environment path
    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $machinePathEntries = $machinePath -split ";"
    $currentPathEntries = $env:Path -split ";"
    foreach ($entry in $machinePathEntries) {
        if ($entry -and -not ($currentPathEntries -contains $entry)) {
            $env:Path += ";$entry"
        }
    }
    Write-Host "PATH environment variable refreshed successfully"
} catch {
    Write-Host "Failed to refresh PATH environment variable: $_" -ForegroundColor Yellow
}

## Apply the dotfiles bootstrap variables
# Get the directory path of the script
$DotfilesRoot = Split-Path -Parent $MyInvocation.MyCommand.Path | Split-Path -Parent

# Get the directory path of the config files
$DotfilesConfigFolder = Join-Path $DotfilesRoot "dotfiles-configurations"
$DotfilesVariablesFile = Get-ChildItem -Path $DotfilesConfigFolder -Filter "dotfiles-bootstrap-variables.json"

if ($DotfilesVariablesFile) {
    $DotfilesVariables = Get-Content -Path $DotfilesVariablesFile.FullName | ConvertFrom-Json
} else {
    Write-Host "The dotfiles-bootstrap-variables.json file was not found in the dotfiles-configurations folder"
    Write-Host "Please make sure that the file exists in " $DotfilesConfigFolder" and try again"
    Exit(1)
}

Write-Host "Dotfiles Bootstrap Variables to be aplied:"
Write-Host $DotfilesVariables | Format-List

# Validate required configuration values
$requiredVars = @("CUSTOM_PROFILE_FOLDER", "WORKSPACE_FOLDER", "GITHUB_ACCOUNT", "GITHUB_DOTFILES_REPO")
$missingVars = $requiredVars | Where-Object { -not $DotfilesVariables.$_ }

if ($missingVars) {
    Write-Host "Missing required configuration variables: $($missingVars -join ', ')" -ForegroundColor Red
    Stop-Transcript
    Exit 1
}

function Enable-DeveloperMode {
    Write-Host "Enabling Developer Mode (requires elevation)..."
    $command = 'reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" /t REG_DWORD /f /v "AllowDevelopmentWithoutDevLicense" /d "1"'
    Start-Process powershell -ArgumentList "-NoProfile -WindowStyle Hidden -Command $command" -Verb RunAs -Wait
    Write-Host "Developer Mode should now be enabled. Please re-run this script if you still see errors."
}

# Check for Developer Mode or admin rights before creating a symbolic link
function Test-DeveloperMode {
    try {
        $reg = Get-ItemProperty -Path "HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\AppModelUnlock" -Name "AllowDevelopmentWithoutDevLicense" -ErrorAction Stop
        return $reg.AllowDevelopmentWithoutDevLicense -eq 1
    } catch {
        return $false
    }
}

if (-not (Test-DeveloperMode)) {
    if (-not ([bool](New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))) {
        Enable-DeveloperMode
        # Re-check Developer Mode after attempting to enable
        if (-not (Test-DeveloperMode)) {
            Write-Host "Failed to enable Developer Mode. Please enable it manually or run this script as Administrator." -ForegroundColor Red
            Stop-Transcript
            Exit 1
        }
    }
}

# Create a symbolic link to the custom profile directory
Write-Host "Creating a symbolic link to the custom profile directory"
$customProfileDirectory = Join-Path $env:USERPROFILE $DotfilesVariables.CUSTOM_PROFILE_FOLDER
$profileDirectory = Split-Path -Parent $PROFILE

if (-not (Test-Path $customProfileDirectory)) {
    try {
        # Try to create a symbolic link
        New-Item -ItemType SymbolicLink -Path $customProfileDirectory -Value $profileDirectory -Force -ErrorAction Stop | Out-Null
        if (Test-Path $customProfileDirectory) {
            Write-Host "Symbolic link to the custom profile directory created successfully"
        } else {
            throw "Unknown error: symlink not created"
        }
    } catch {
        Write-Warning "Failed to create a symbolic link: $($_.Exception.Message)"
        Write-Host "Attempting to create a normal directory as a fallback..."
        try {
            New-Item -ItemType Directory -Path $customProfileDirectory -Force -ErrorAction Stop | Out-Null
            Write-Warning "Fallback: Created a normal directory instead of a symlink. Some features may not work as intended."
        } catch {
            Write-Host "Failed to create the custom profile directory. Exiting script. Error: $($_.Exception.Message)"
            Stop-Transcript
            Exit 1
        }
    }
} else {
    Write-Host "Custom profile directory already exists: $customProfileDirectory"
}

# Create workspace directory if it does not exist
Write-Host "Creating workspace directory"
$workspaceDirectory = Join-Path $env:USERPROFILE $DotfilesVariables.WORKSPACE_FOLDER
if (-not (Test-Path $workspaceDirectory)) {
    #create the workspace directory
    New-Item -ItemType Directory -Path $workspaceDirectory -Force | Out-Null
}

# Clone the dotfiles repository if it does not exist
Write-Host "Cloning the dotfiles repository"
$dotfilesRepositoryURL = "https://github.com/$($DotfilesVariables.GITHUB_ACCOUNT)/$($DotfilesVariables.GITHUB_DOTFILES_REPO).git"
$dotfilesDirectory = Join-Path $workspaceDirectory $DotfilesVariables.GITHUB_DOTFILES_REPO
if (-not (Test-Path $dotfilesDirectory)) {
    #clone the dotfiles repository
    git clone $dotfilesRepositoryURL $dotfilesDirectory

    # Verify cloning succeeded
    if (-not (Test-Path $dotfilesDirectory)) {
        Write-Host "Failed to clone the dotfiles repository. Exiting script."
        Stop-Transcript
        Exit 1
    }
}

# Change the working directory to the dotfiles repository
Set-Location $dotfilesDirectory
$DotfilesSetupScriptsFolder = Join-Path $dotfilesDirectory "setup-scripts"

# Run the setup scripts
Write-Host "Running the setup scripts"

# For each script in the setup-scripts folder started with setup.ps7, run the script
$setupScripts = Get-ChildItem -Path $DotfilesSetupScriptsFolder -Filter "setup.ps7-*.ps1"

# Create a dictionary to store the script names and their exit codes
$scriptResults = @{}

foreach ($script in $setupScripts) {
    Write-Host "Running $($script.Name)" -ForegroundColor Cyan
    try {
        if($script.Name -like "*admin*") {
            $process = Start-Process -FilePath "pwsh.exe" -ArgumentList "-File $($script.FullName)" -Verb RunAs -PassThru -Wait
        } else {
            $process = Start-Process -FilePath "pwsh.exe" -ArgumentList "-File $($script.FullName)" -PassThru -Wait
        }
        $scriptResults.Add($script.Name, $process.ExitCode)
        if ($process.ExitCode -eq 0) {
            Write-Host "Script $($script.Name) completed successfully" -ForegroundColor Green
        } else {
            Write-Host "Script $($script.Name) exited with code: $($process.ExitCode)" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "Failed to execute $($script.Name): $_" -ForegroundColor Red
    }
}

# Display summary
Write-Host "`n==================== SETUP SUMMARY ====================" -ForegroundColor Cyan
Write-Host "PowerShell 7 Installed: $(if (Get-Command pwsh -ErrorAction SilentlyContinue) {'Yes'} else {'No'})"
Write-Host "Git Installed: $(if (Get-Command git -ErrorAction SilentlyContinue) {'Yes'} else {'No'})"
Write-Host "Workspace Directory: $workspaceDirectory ($(if (Test-Path $workspaceDirectory) {'Exists'} else {'Missing'}))"
Write-Host "Dotfiles Repository: $dotfilesDirectory ($(if (Test-Path $dotfilesDirectory) {'Cloned'} else {'Missing'}))"
Write-Host "Custom Profile Directory: $customProfileDirectory ($(if (Test-Path $customProfileDirectory) {'Linked'} else {'Missing'}))"
Write-Host "Setup Scripts Results:"
foreach ($script in $scriptResults.Keys) {
    Write-Host " $script ": " $($scriptResults[$script])"
}
Write-Host "Log File: $logFile"
Write-Host "========================================================"

# stop logging
Stop-Transcript
