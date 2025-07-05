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

# Run the setup scripts
Write-Info "Running the setup scripts"

# For each script in the setup-scripts folder started with setup.ps7, run the script
$setupScripts = Get-ChildItem -Path $DotfilesSetupScriptsFolder -Filter "setup.ps7-*.ps1"
$setupScripts = $setupScripts | Sort-Object Name

# For testing purposes, you can uncomment the line below to don't run any setup scripts
# $setupScripts = @() # Uncomment this line to skip running setup scripts

if (-not $setupScripts) {
    Write-WarningMessage "No setup scripts found in $DotfilesSetupScriptsFolder"
    Stop-Logging
    Exit 0
}
# Create a dictionary to store the script names and their exit codes
$scriptResults = @{}

foreach ($script in $setupScripts) {
    Write-Info "Running $($script.Name)"
    try {
        $scriptArg = "-File `"$($script.FullName)`""
        if($script.Name -like "*admin*") {
            $process = Start-Process -FilePath "pwsh.exe" -ArgumentList $scriptArg -Verb RunAs -PassThru -Wait
        } else {
            $process = Start-Process -FilePath "pwsh.exe" -ArgumentList $scriptArg -PassThru -Wait
        }
        $scriptResults.Add($script.Name, $process.ExitCode)
        if ($process.ExitCode -eq 0) {
            Write-Info "Script $($script.Name) completed successfully"
        } else {
            Write-WarningMessage "Script $($script.Name) exited with code: $($process.ExitCode)"
        }
    } catch {
        Write-ErrorMessage "Failed to execute $($script.Name): $_"
    }
}

# Display summary
Write-Info "`n==================== SETUP SUMMARY ===================="
Write-Info "PowerShell 7 Installed: $(if (Get-Command pwsh -ErrorAction SilentlyContinue) {'Yes'} else {'No'})"
Write-Info "Git Installed: $(if (Get-Command git -ErrorAction SilentlyContinue) {'Yes'} else {'No'})"
Write-Info "Workspace Directory: $workspaceDirectory ($(if (Test-Path $workspaceDirectory) {'Exists'} else {'Missing'}))"
Write-Info "Dotfiles Repository: $dotfilesDirectory ($(if (Test-Path $dotfilesDirectory) {'Cloned'} else {'Missing'}))"
Write-Info "Custom Profile Directory: $customProfileDirectory ($(if (Test-Path $customProfileDirectory) {'Linked'} else {'Missing'}))"
Write-Info "Setup Scripts Results:"
foreach ($script in $scriptResults.Keys) {
    Write-Info " $script : $($scriptResults[$script])"
}
Write-Info "Log File: $logFile"
Write-Info "========================================================"

# stop logging
Stop-Logging