<#
.SYNOPSIS
Main bootstrap script.

.DESCRIPTION
This script installs the pre-requisites and starts the other setup scripts with Powershell 7 
It also creates a symbolic link to the custom profile directory and clones the dotfiles repository

.NOTES
To make this work, you need to set your execution policy to unrestricted (or at least bypass) by running Set-ExecutionPolicy Unrestricted -Scope CurrentUser from a PowerShell.

#>

. "$PSScriptRoot\setup-functions.ps1"

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
$prerequisitesInstalled = Install-DotfilesPrerequisites

if (-not $prerequisitesInstalled) {
    Write-ErrorMessage "Failed to install prerequisites. Exiting script."
    Stop-Logging
    Exit 1
} else {
    Write-Info "Prerequisites installed successfully."
}

# Update the environment PATH variable to include the system PATH
# This is necessary for the script to find the WinGet Cmdlet and other system tools
Write-Info "Refreshing PATH environment variable..."
try {
    $env:Path += ";" + [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    Write-Info "PATH environment variable refreshed successfully"
} catch {
    Write-WarningMessage "Failed to refresh PATH environment variable: $_"
}

# Apply the dotfiles bootstrap variables
Write-Info "Applying dotfiles bootstrap variables..."
$DotfilesVariables = Get-DotfilesBootstrapVariables
if (-not $DotfilesVariables) {
    Write-WarningMessage "No dotfiles bootstrap variables found."
    Stop-Transcript
    Exit 1
}

# Validate required configuration values
$requiredVars = @("CUSTOM_PROFILE_FOLDER", "WORKSPACE_FOLDER", "GITHUB_ACCOUNT", "GITHUB_DOTFILES_REPO")
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
    # Check if running as administrator
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-WarningMessage "Symlink creation requires elevated privileges. Relaunching this block as administrator..."
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
                Write-Info "Symbolic link to the custom profile directory created successfully"
            } else {
                throw "Unknown error: symlink not created"
            }
        } catch {
            Write-WarningMessage "Failed to create a symbolic link: $($_.Exception.Message)"
        }
    }
}

# Create workspace directory if it does not exist
Write-Info "Creating workspace directory"
$workspaceDirectory = Join-Path $env:USERPROFILE $DotfilesVariables.WORKSPACE_FOLDER
if (-not (Test-Path $workspaceDirectory)) {
    #create the workspace directory
    New-Item -ItemType Directory -Path $workspaceDirectory -Force | Out-Null
} else {
    Write-Info "Workspace directory already exists: $workspaceDirectory"
}

# Clone the dotfiles repository if it does not exist
Write-Info "Cloning the dotfiles repository"
$dotfilesRepositoryURL = "https://github.com/$($DotfilesVariables.GITHUB_ACCOUNT)/$($DotfilesVariables.GITHUB_DOTFILES_REPO).git"
$dotfilesDirectory = Join-Path $workspaceDirectory $DotfilesVariables.GITHUB_DOTFILES_REPO
if (-not (Test-Path $dotfilesDirectory)) {
    # clone the dotfiles repository
    Write-Info "Cloning repository from $dotfilesRepositoryURL"
    $cloneOutput = git clone $dotfilesRepositoryURL $dotfilesDirectory 2>&1
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $dotfilesDirectory)) {
        Write-ErrorMessage "Failed to clone the dotfiles repository:`n$cloneOutput"
        Stop-Logging
        Exit 1
    }
} else {
    Write-Info "Dotfiles directory already exists: $dotfilesDirectory"
}

# Change the working directory to the dotfiles repository
Set-Location $dotfilesDirectory
$DotfilesSetupScriptsFolder = Join-Path $dotfilesDirectory "setup-scripts"

# Run the new modular setup scripts
Write-Info "Running the modular setup scripts from 'setup-modules'..."

$moduleScriptsPath = Join-Path $dotfilesDirectory "setup-modules"
$modulesToRun = @(
    "Configure-WindowsFeatures.ps1",
    "Install-WingetPackages.ps1",
    "Set-EnvironmentVariables.ps1",
    "Apply-GitConfig.ps1"
)

# Modules that require administrator privileges
$adminModules = @(
    "Configure-WindowsFeatures.ps1"
)

if (-not (Test-Path $moduleScriptsPath)) {
    Write-ErrorMessage "The 'setup-modules' directory was not found at '$moduleScriptsPath'."
    Stop-Logging
    Exit 1
}

$scriptResults = @{}

foreach ($moduleName in $modulesToRun) {
    $modulePath = Join-Path $moduleScriptsPath $moduleName
    if (-not (Test-Path $modulePath)) {
        Write-WarningMessage "Module script not found: $moduleName. Skipping."
        continue
    }

    Write-Info "Running module: $moduleName"
    try {
        $scriptArg = "-File `"$modulePath`""
        $requiresAdmin = $adminModules -contains $moduleName

        # Check if running as administrator
        $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

        if ($requiresAdmin -and -not $isAdmin) {
            Write-WarningMessage "Module '$moduleName' requires elevated privileges. Relaunching this module as administrator..."
            $process = Start-Process -FilePath "pwsh.exe" -ArgumentList $scriptArg -Verb RunAs -PassThru -Wait
        } else {
            $process = Start-Process -FilePath "pwsh.exe" -ArgumentList $scriptArg -PassThru -Wait
        }

        $scriptResults.Add($moduleName, $process.ExitCode)
        if ($process.ExitCode -eq 0) {
            Write-Info "Module '$moduleName' completed successfully."
        } else {
            Write-ErrorMessage "Module '$moduleName' exited with code: $($process.ExitCode). Halting setup."
            Stop-Logging
            Exit 1 # Stop the entire setup if a module fails
        }
    } catch {
        Write-ErrorMessage "Failed to execute module '$moduleName': $_"
        Stop-Logging
        Exit 1
    }
}

# Display summary
Write-Info "`n==================== SETUP SUMMARY ===================="
Write-Info "PowerShell 7 Installed: $(if (Get-Command pwsh -ErrorAction SilentlyContinue) {'Yes'} else {'No'})"
Write-Info "Git Installed: $(if (Get-Command git -ErrorAction SilentlyContinue) {'Yes'} else {'No'})"
Write-Info "Workspace Directory: $workspaceDirectory ($(if (Test-Path $workspaceDirectory) {'Exists'} else {'Missing'}))"
Write-Info "Dotfiles Repository: $dotfilesDirectory ($(if (Test-Path $dotfilesDirectory) {'Cloned'} else {'Missing'}))"
Write-Info "Custom Profile Directory: $customProfileDirectory ($(if (Test-Path $customProfileDirectory) {'Linked'} else {'Missing'}))"
Write-Info "Setup Modules Results:"
foreach ($module in $scriptResults.Keys) {
    $status = if ($scriptResults[$module] -eq 0) { "Success" } else { "Failed" }
    Write-Info " - $module : $status (Exit Code: $($scriptResults[$module]))"
}
Write-Info "Log File: $logFile"
Write-Info "========================================================"

# stop logging
Stop-Logging