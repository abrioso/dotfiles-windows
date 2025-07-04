<#
.SYNOPSIS
Main bootstrap script.

.DESCRIPTION
This script installs the pre-requisites and starts the other setup scripts with Powershell 7 
It also creates a symbolic link to the custom profile directory and clones the dotfiles repository

.NOTES
To make this work, you need to set your execution policy to unrestricted (or at least bypass) by running Set-ExecutionPolicy Unrestricted -Scope CurrentUser from a PowerShell.

#>

Import-Module "$PSScriptRoot\setup-functions.ps1"

# Variables for logging
$dateTime = Get-Date -Format "yyyyMMdd-HHmmss"
$logDir = Split-Path -Parent $PSScriptRoot
$logDir = Join-Path $logDir "logs"
$scriptName = Split-Path -Leaf $PSCommandPath
$logFile = "$logDir/$scriptName-$dateTime.txt"

# Start logging
Start-Logging -LogFilePath $logFile

# Check execution policy at script start
$currentPolicy = Get-ExecutionPolicy
Write-Host "Current execution policy: $currentPolicy"
if ($currentPolicy -in @("Restricted", "AllSigned")) {
    Write-Warning "Current execution policy may prevent script execution"
    Write-Warning "Consider running: Set-ExecutionPolicy RemoteSigned -Scope CurrentUser or Set-ExecutionPolicy Unrestricted -Scope CurrentUser"
}

Write-Host "Installing the pre-requisites for the dotfiles setup:"

# Check if NuGet provider is installed
if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
    Write-Host "NuGet provider is not installed. Installing now..."
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser
    Import-PackageProvider -Name NuGet -Force
} else {
    Write-Host "  NuGet provider is already installed, skipping installation."
}

# Determine if winget is available
$wingetAvailable = Get-Command winget -ErrorAction SilentlyContinue
if($wingetAvailable) {
    Write-Host "  Winget is available, proceeding with installations."
} else {
    Write-Warning "  Winget is not available. Some installations may not work as expected."
}

# Install PowerShell if not present
if (-not (Get-Command pwsh -ErrorAction SilentlyContinue)) {
    Write-Host "  PowerShell is not installed. Installing PowerShell..."
    if ($wingetAvailable) {
        try {
            $result = winget install --id Microsoft.PowerShell -e --scope machine --force --accept-source-agreements --accept-package-agreements
            if ($LASTEXITCODE -ne 0) { throw "Failed to install PowerShell: " + $result }
        } catch {
            Write-Host "    Error installing PowerShell: $_" -ForegroundColor Red
            Write-Host "    Continuing with script, but some features may not work correctly."
        }
    } else {
        Write-Warning "  Winget is not available. Please install PowerShell manually."
    }
} else {
    Write-Host "  PowerShell 7 is already installed, skipping installation."
}


# Ensure NuGet and PowerShellGet are up to date
# Check and update NuGet provider
$nugetProvider = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
if (-not $nugetProvider -or $nugetProvider.Version -lt [Version]'2.8.5.201') {
    Write-Host "  Updating NuGet provider..."
    try {
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser -ErrorAction Stop
        Import-PackageProvider -Name NuGet -Force
    } catch {
        Write-Warning "  Failed to update NuGet provider: $_"
    }
} else {
    Write-Host "  NuGet provider is up to date."
}

# Check and update PowerShellGet
$psGetModule = Get-Module -ListAvailable PowerShellGet | Sort-Object Version -Descending | Select-Object -First 1
if ($psGetModule.Version -lt [Version]'2.2.5') {
    Write-Host "  Updating PowerShellGet module..."
    try {
        Install-Module -Name PowerShellGet -Force -Scope CurrentUser -ErrorAction Stop
        Write-Host "  PowerShellGet updated. Please restart PowerShell to use the new version."
    } catch {
        Write-Warning "  Failed to update PowerShellGet: $_"
    }
} else {
    Write-Host "  PowerShellGet is up to date."
}


# Determine if -AcceptLicense switch is supported
$psGetVersion = (Get-Module PowerShellGet -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1).Version
$installModuleParams = @{}
if ($psGetVersion -ge [Version]"2.0.0") {
    $installModuleParams.AcceptLicense = $true
}


# Install Git if not present
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "  Git not found. Installing Git..."
    if ($wingetAvailable) {
        try {
            $result = winget install --id Git.Git -e --force --accept-source-agreements --accept-package-agreements
            if ($LASTEXITCODE -ne 0) { throw "Failed to install Git: " + $result }
        } catch {
            Write-Host "Error installing Git: $_" -ForegroundColor Red
            Write-Host "Continuing with script, but some features may not work correctly."
        }
    } else {
        Write-Warning "  Winget is not available. Please install Git manually."
    }
} else {
    Write-Host "  Git is already installed, skipping installation."
}

# Ensure the PSGallery repository is registered
try {
    $psGallery = Get-PSRepository -Name "PSGallery" -ErrorAction Stop
    if ($psGallery -and $psGallery.InstallationPolicy -ne "Trusted") {
        Write-Host "  PSGallery repository is not trusted. Setting it to Trusted..."
        Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted
    }
} catch {
    if ($_.Exception.Message -like '*already exists*') {
        Write-Host "  PSGallery repository already exists. Skipping registration."
    } else {
        Write-Host "  PSGallery repository not found. Registering it now..."
        try {
            Register-PSRepository -Default -ErrorAction Stop
        } catch {
            Write-Host "  Failed to register PSGallery repository: $_" -ForegroundColor Red
        }
    }
}

# Register the default repository if not already registered
if (-not (Get-PSRepository -Name "PSGallery" -ErrorAction SilentlyContinue)) {
    Write-Host "  Registering default PowerShell repository..."
    Register-PSRepository -Default
}

# Install the Winget Cmdlet required for enabling Windows features and system-level installation
Write-Host "  Ensuring the Winget Cmdlet is installed..."

# Only install the module if it isn't already installed
if (-not (Get-Module -ListAvailable -Name Microsoft.WinGet.Configuration)) {
    Write-Host "  Installing the Microsoft.WinGet.Configuration module..."
    try {
        Install-Module -Name Microsoft.WinGet.Configuration -Force -Scope CurrentUser @installModuleParams
        Write-Host "  Microsoft.WinGet.Configuration module installed."
    } catch {
        Write-Warning "  Failed to install Microsoft.WinGet.Configuration: $_"
    }
} else {
    Write-Host "  Microsoft.WinGet.Configuration module is already installed, skipping installation."
}

# Update the system PATH variable properly
# This is necessary to ensure that the PATH variable is up-to-date with the latest changes
Write-Host "Refreshing PATH environment variable..."
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

# Apply the dotfiles bootstrap variables
Write-Host "Applying dotfiles bootstrap variables..."
$DotfilesVariables = Get-DotfilesBootstrapVariables

# Validate required configuration values
$requiredVars = @("CUSTOM_PROFILE_FOLDER", "WORKSPACE_FOLDER", "GITHUB_ACCOUNT", "GITHUB_DOTFILES_REPO")
$missingVars = $requiredVars | Where-Object { -not $DotfilesVariables.$_ }

if ($missingVars) {
    Write-Host "Missing required configuration variables: $($missingVars -join ', ')" -ForegroundColor Red
    Stop-Logging
    Exit 1
}

# Create a symbolic link to the custom profile directory
Write-Host "Creating a symbolic link to the custom profile directory"
$customProfileDirectory = Join-Path $env:USERPROFILE $DotfilesVariables.CUSTOM_PROFILE_FOLDER
$profileDirectory = Split-Path -Parent $PROFILE

# Create a symlink to the custom profile directory if it does not exist or is not a symlink
$createSymlink = $false
if (Test-Path $customProfileDirectory) {
    $item = Get-Item $customProfileDirectory -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        Write-Host "Custom profile directory already exists as a symlink: $customProfileDirectory"
    } else {
        Write-Host "Custom profile directory exists as a normal directory."
        $userInput = Read-Host "Do you want to delete this directory and replace it with a symlink? (Y/N)"
        if ($userInput -match '^(Y|y)') {
            Write-Host "Removing directory..."
            Remove-Item $customProfileDirectory -Recurse -Force
            $createSymlink = $true
        } else {
            Write-Warning "Symlink creation skipped. Directory was not removed."
        }
    }
} else {
    $createSymlink = $true
}

if ($createSymlink) {
    # Check if running as administrator
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Host "Symlink creation requires elevated privileges. Relaunching this block as administrator..."
        $symlinkScript = @"
try {
    New-Item -ItemType SymbolicLink -Path '$customProfileDirectory' -Value '$profileDirectory' -Force -ErrorAction Stop | Out-Null
    if (Test-Path '$customProfileDirectory') {
        Write-Host 'Symbolic link to the custom profile directory created successfully'
    } else {
        throw 'Unknown error: symlink not created'
    }
} catch {
    Write-Warning "Failed to create a symbolic link: $($_.Exception.Message)"
}
"@
        $tempScriptPath = [System.IO.Path]::GetTempFileName() + '.ps1'
        Set-Content -Path $tempScriptPath -Value $symlinkScript -Encoding UTF8
        Start-Process -FilePath 'pwsh.exe' -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$tempScriptPath`"" -Verb RunAs -Wait
        Remove-Item $tempScriptPath -Force
    } else {
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
        }
    }
}

# Create workspace directory if it does not exist
Write-Host "Creating workspace directory"
$workspaceDirectory = Join-Path $env:USERPROFILE $DotfilesVariables.WORKSPACE_FOLDER
if (-not (Test-Path $workspaceDirectory)) {
    #create the workspace directory
    New-Item -ItemType Directory -Path $workspaceDirectory -Force | Out-Null
} else {
    Write-Host "Workspace directory already exists: $workspaceDirectory"
}

# Clone the dotfiles repository if it does not exist
Write-Host "Cloning the dotfiles repository"
$dotfilesRepositoryURL = "https://github.com/$($DotfilesVariables.GITHUB_ACCOUNT)/$($DotfilesVariables.GITHUB_DOTFILES_REPO).git"
$dotfilesDirectory = Join-Path $workspaceDirectory $DotfilesVariables.GITHUB_DOTFILES_REPO
if (-not (Test-Path $dotfilesDirectory)) {
    # clone the dotfiles repository
    Write-Host "Cloning repository from $dotfilesRepositoryURL"
    $cloneOutput = git clone $dotfilesRepositoryURL $dotfilesDirectory 2>&1
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $dotfilesDirectory)) {
        Write-Host "Failed to clone the dotfiles repository:`n$cloneOutput" -ForegroundColor Red
        Stop-Logging
        Exit 1
    }
} else {
    Write-Host "Dotfiles directory already exists: $dotfilesDirectory"
}

# Change the working directory to the dotfiles repository
Set-Location $dotfilesDirectory
$DotfilesSetupScriptsFolder = Join-Path $dotfilesDirectory "setup-scripts"

# Run the setup scripts
Write-Host "Running the setup scripts"

# For each script in the setup-scripts folder started with setup.ps7, run the script
$setupScripts = Get-ChildItem -Path $DotfilesSetupScriptsFolder -Filter "setup.ps7-*.ps1"
$setupScripts = $setupScripts | Sort-Object Name

# For testing purposes, you can uncomment the line below to don't run any setup scripts
 $setupScripts = @() # Uncomment this line to skip running setup scripts

if (-not $setupScripts) {
    Write-Host "No setup scripts found in $DotfilesSetupScriptsFolder" -ForegroundColor Yellow
    Stop-Logging
    Exit 0
}
# Create a dictionary to store the script names and their exit codes
$scriptResults = @{}

foreach ($script in $setupScripts) {
    Write-Host "Running $($script.Name)" -ForegroundColor Cyan
    try {
        $scriptArg = "-File `"$($script.FullName)`""
        if($script.Name -like "*admin*") {
            $process = Start-Process -FilePath "pwsh.exe" -ArgumentList $scriptArg -Verb RunAs -PassThru -Wait
        } else {
            $process = Start-Process -FilePath "pwsh.exe" -ArgumentList $scriptArg -PassThru -Wait
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
Stop-Logging