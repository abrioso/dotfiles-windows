<#
.SYNOPSIS
Main bootstrap script.

.DESCRIPTION
This script installs the pre-requisites and starts the other setup scripts with Powershell 7 
It also creates a symbolic link to the custom profile directory and clones the dotfiles repository

.NOTES
To make this work, you need to set your execution policy to unrestricted (or at least bypass) by running Set-ExecutionPolicy Unrestricted -Scope CurrentUser from a PowerShell.

#>

[CmdletBinding()]
param (
    [string]$BootstrapBranch,
    [switch]$NonInteractive
)

# dotfileRootDir is the root directory of the dotfiles repository
$dotfileRootDir = Split-Path -Parent $PSScriptRoot

. "$dotfileRootDir\setup-scripts\setup-functions.ps1"

# Variables for logging
$dateTime = Get-Date -Format "yyyyMMdd-HHmmss"
$logDir = Join-Path $dotfileRootDir "logs"
$scriptName = Split-Path -Leaf $PSCommandPath
$logFile = "$logDir/$scriptName-$dateTime.txt"

# Start logging
$logFile = Start-Logging -LogFilePath $logFile -PassThru

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

# Refresh PATH after installing per-user prerequisites.
Write-Info "Refreshing PATH environment variable..."
try {
    Update-DotfilesProcessPath
    Write-Info "PATH environment variable refreshed successfully"
} catch {
    Write-WarningMessage "Failed to refresh PATH environment variable: $_"
}

# Windows PowerShell treats normal native stderr output (for example, Git progress)
# as PowerShell errors when it is redirected. Continue the bootstrap in PowerShell 7
# before running any Git commands so callers can safely start from Windows PowerShell 5.1.
if ($PSVersionTable.PSEdition -ne "Core") {
    $pwshCommand = Get-Command pwsh -ErrorAction SilentlyContinue
    if (-not $pwshCommand) {
        Write-ErrorMessage "PowerShell 7 is installed but pwsh could not be resolved for bootstrap relaunch."
        Stop-Logging
        Exit 1
    }

    $pwshArguments = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $PSCommandPath)
    if (-not [string]::IsNullOrWhiteSpace($BootstrapBranch)) {
        $pwshArguments += @("-BootstrapBranch", $BootstrapBranch)
    }
    if ($NonInteractive) {
        $pwshArguments += "-NonInteractive"
    }

    Write-Info "Relaunching bootstrap in PowerShell 7..."
    Stop-Logging
    & $pwshCommand.Source @pwshArguments
    Exit $LASTEXITCODE
}

# Apply the dotfiles bootstrap variables
Write-Info "Applying dotfiles bootstrap variables..."
$DotfilesVariables = Get-DotfilesBootstrapVariables -NonInteractive:$NonInteractive
if (-not $DotfilesVariables) {
    Write-WarningMessage "No dotfiles bootstrap variables found."
    Stop-Transcript
    Exit 1
}

# Validate required configuration values
$requiredVars = @("WORKSPACE_FOLDER", "GITHUB_ACCOUNT", "GITHUB_DOTFILES_REPO")
$missingVars = $requiredVars | Where-Object { -not $DotfilesVariables.$_ }

if ($missingVars) {
    Write-ErrorMessage "Missing required configuration variables: $($missingVars -join ', ')"
    Stop-Logging
    Exit 1
}

if (-not [string]::IsNullOrWhiteSpace($BootstrapBranch)) {
    Write-Info "Using bootstrap branch override: $BootstrapBranch"
    $DotfilesVariables.GITHUB_DOTFILES_BRANCH = $BootstrapBranch
    $bootstrapConfigPath = Join-Path $dotfileRootDir "dotfiles-configurations\dotfiles-bootstrap-variables.json"
    Set-DotfilesBootstrapBranch -ConfigPath $bootstrapConfigPath -Branch $BootstrapBranch
}


# Create workspace directory if it does not exist
Write-Info "Creating workspace directory"
$workspaceDirectory = Join-Path $env:USERPROFILE $DotfilesVariables.WORKSPACE_FOLDER
if (-not (Test-Path -LiteralPath $workspaceDirectory)) {
    #create the workspace directory
    New-Item -ItemType Directory -Path $workspaceDirectory -Force | Out-Null
} else {
    Write-Info "Workspace directory already exists: $workspaceDirectory"
}

# Clone the dotfiles repository if it does not exist
Write-Info "Cloning the dotfiles repository"
$dotfilesRepositoryURL = Resolve-DotfilesRepositoryUrl -DotfilesVariables $DotfilesVariables
$dotfilesDirectory = Join-Path $workspaceDirectory $DotfilesVariables.GITHUB_DOTFILES_REPO
if (-not (Test-Path -LiteralPath $dotfilesDirectory)) {
    # clone the dotfiles repository
    Write-Info "Cloning repository from $dotfilesRepositoryURL"
    $cloneOutput = git clone $dotfilesRepositoryURL $dotfilesDirectory 2>&1
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $dotfilesDirectory)) {
        Write-ErrorMessage "Failed to clone the dotfiles repository:`n$cloneOutput"
        Stop-Logging
        Exit 1
    }
} else {
    Write-Info "Dotfiles directory already exists: $dotfilesDirectory"
}

# Change the working directory to the dotfiles repository
Set-Location -LiteralPath $dotfilesDirectory

if ($DotfilesVariables.GITHUB_DOTFILES_BRANCH) {
    Write-Info "Ensuring dotfiles repository is on branch '$($DotfilesVariables.GITHUB_DOTFILES_BRANCH)'..."
    git fetch origin $DotfilesVariables.GITHUB_DOTFILES_BRANCH 2>&1 | Out-Host
    if ($LASTEXITCODE -ne 0) {
        Write-ErrorMessage "Failed to fetch branch '$($DotfilesVariables.GITHUB_DOTFILES_BRANCH)' from origin."
        Stop-Logging
        Exit 1
    }

    git checkout $DotfilesVariables.GITHUB_DOTFILES_BRANCH 2>&1 | Out-Host
    if ($LASTEXITCODE -ne 0) {
        Write-ErrorMessage "Failed to checkout branch '$($DotfilesVariables.GITHUB_DOTFILES_BRANCH)'."
        Stop-Logging
        Exit 1
    }

    git pull --ff-only origin $DotfilesVariables.GITHUB_DOTFILES_BRANCH 2>&1 | Out-Host
    if ($LASTEXITCODE -ne 0) {
        Write-ErrorMessage "Failed to pull latest changes for branch '$($DotfilesVariables.GITHUB_DOTFILES_BRANCH)'."
        Stop-Logging
        Exit 1
    }
}

# Ensure gitignored local configuration generated in the bootstrap copy follows the real clone
# after checkout/pull, so tracked JSON files deleted by this commit cannot mask local config copies.
Sync-DotfilesLocalConfiguration -SourceRoot $dotfileRootDir -TargetRoot $dotfilesDirectory

# Run the new modular setup scripts
Write-Info "Running the modular setup scripts from 'setup-modules'..."

$moduleScriptsPath = Join-Path $dotfilesDirectory "setup-modules"
$moduleConfigDirectory = Join-Path $dotfilesDirectory "dotfiles-configurations"
$moduleLogDirectory = Join-Path $dotfilesDirectory "logs"
Assert-DotfilesSetupDependencies -DotfilesVariables $DotfilesVariables -ConfigDirectory $moduleConfigDirectory
$modulesToRun = Get-DotfilesSetupPlan -DotfilesVariables $DotfilesVariables -ConfigDirectory $moduleConfigDirectory

if (-not (Test-Path -LiteralPath $moduleScriptsPath)) {
    Write-ErrorMessage "The 'setup-modules' directory was not found at '$moduleScriptsPath'."
    Stop-Logging
    Exit 1
}

$scriptResults = @{}

function Write-ModuleLogLocation {
    param([string]$ModuleLogFile)

    if ([string]::IsNullOrWhiteSpace($ModuleLogFile)) {
        return
    }
    if (Test-Path -LiteralPath $ModuleLogFile -PathType Leaf) {
        Write-Info "Module log: $ModuleLogFile"
    } else {
        Write-WarningMessage "The module did not create its expected log file: $ModuleLogFile"
    }
}

:moduleLoop foreach ($module in $modulesToRun) {
    $moduleName = $module.Script
    $modulePath = Join-Path $moduleScriptsPath $moduleName
    if (-not (Test-Path -LiteralPath $modulePath)) {
        Write-ErrorMessage "Module script not found: $moduleName."
        Stop-Logging
        Exit 1
    }

    Write-Info "Running module: $moduleName"
    try {
        $moduleLogFile = $null
        $requiresAdmin = $module.RequiresAdmin
        if ($moduleName -eq 'Configure-WindowsFeatures.ps1') {
            $requestedFeatures = @(Resolve-DotfilesWindowsFeature `
                -ConfigPath (Join-Path $moduleConfigDirectory 'windows-features.json') `
                -BootstrapPath (Join-Path $moduleConfigDirectory 'dotfiles-bootstrap-variables.json'))
            if (Test-DotfilesWindowsFeaturesEnabled -FeatureName $requestedFeatures) {
                Write-Info 'All requested Windows features are already enabled. Skipping elevation.'
                $scriptResults.Add($moduleName, 0)
                continue
            }
        }
        elseif ($moduleName -eq 'Set-UserHomeAlias.ps1') {
            $userProfile = [System.Environment]::GetEnvironmentVariable('USERPROFILE', 'Process')
            if ([string]::IsNullOrWhiteSpace($userProfile)) {
                throw 'USERPROFILE is not set; cannot preflight the home alias.'
            }

            $aliasName = $null
            $hasNonAsciiCharacter = @($userProfile.ToCharArray() | Where-Object { [int]$_ -gt 127 }).Count -gt 0
            if ($hasNonAsciiCharacter) {
                $windowsIdentityName = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
                $aliasName = Resolve-DotfilesUserHomeAliasName -WindowsIdentityName $windowsIdentityName -UserName $env:USERNAME
            }
            $currentHome = [System.Environment]::GetEnvironmentVariable('HOME', 'User')
            $homeAliasPreflight = Get-DotfilesUserHomeAliasPreflight `
                -UserProfile $userProfile `
                -AliasName $aliasName `
                -CurrentHome $currentHome

            switch ($homeAliasPreflight.Action) {
                'Skip' {
                    Write-Info $homeAliasPreflight.Message
                    $scriptResults.Add($moduleName, 0)
                    continue moduleLoop
                }
                'RunNonElevated' {
                    Write-Info $homeAliasPreflight.Message
                    $requiresAdmin = $false
                }
                'Elevate' {
                    Write-Info $homeAliasPreflight.Message
                    # Older gitignored setup-modules.json files may not carry requiresAdmin yet.
                    $requiresAdmin = $true
                }
                'Fail' {
                    throw $homeAliasPreflight.Message
                }
                default {
                    throw "Unknown home alias preflight action '$($homeAliasPreflight.Action)'."
                }
            }
        }

        $moduleHost = if ($moduleName -eq 'Configure-WindowsFeatures.ps1') {
            Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        } else {
            'pwsh.exe'
        }
        if ($moduleName -eq 'Configure-WindowsFeatures.ps1' -and -not (Test-Path -LiteralPath $moduleHost -PathType Leaf)) {
            throw "Windows PowerShell 5.1 was not found at '$moduleHost'."
        }

        $moduleArguments = @('-NoProfile', '-File', $modulePath)
        $scriptArg = "-NoProfile -File `"$modulePath`""
        if ($moduleName -in @('Configure-WindowsFeatures.ps1', 'Set-UserHomeAlias.ps1')) {
            $moduleLogName = "{0}-{1}-{2}.txt" -f $moduleName, (Get-Date -Format 'yyyyMMdd-HHmmssfff'), [System.Guid]::NewGuid().ToString('N').Substring(0, 8)
            $moduleLogFile = Join-Path $moduleLogDirectory $moduleLogName
            $moduleArguments += @('-LogFilePath', $moduleLogFile)
            $scriptArg += " -LogFilePath `"$moduleLogFile`""
        }

        # Check if running as administrator
        $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

        if ($requiresAdmin -and -not $isAdmin) {
            Write-WarningMessage "Module '$moduleName' requires elevated privileges. Relaunching this module as administrator..."
            $process = Start-Process -FilePath $moduleHost -ArgumentList $scriptArg -WorkingDirectory $dotfilesDirectory -Verb RunAs -PassThru -Wait
            $moduleExitCode = $process.ExitCode
        } else {
            & $moduleHost @moduleArguments
            $moduleExitCode = $LASTEXITCODE
        }

        $scriptResults.Add($moduleName, $moduleExitCode)
        if ($moduleExitCode -eq 3010) {
            Write-WarningMessage "Module '$moduleName' enabled Windows features that require a restart. Restart Windows, then re-run setup to continue."
            Write-ModuleLogLocation -ModuleLogFile $moduleLogFile
            Stop-Logging
            Exit 3010
        }
        if ($moduleExitCode -eq 0) {
            Write-Info "Module '$moduleName' completed successfully."
        } else {
            Write-ErrorMessage "Module '$moduleName' exited with code: $moduleExitCode. Halting setup."
            Write-ModuleLogLocation -ModuleLogFile $moduleLogFile
            Stop-Logging
            Exit 1 # Stop the entire setup if a module fails
        }
    } catch {
        Write-ErrorMessage "Failed to execute module '$moduleName': $_"
        Write-ModuleLogLocation -ModuleLogFile $moduleLogFile
        Stop-Logging
        Exit 1
    }
}

# Display summary
Write-Info "`n==================== SETUP SUMMARY ===================="
Write-Info "PowerShell 7 Installed: $(if (Get-Command pwsh -ErrorAction SilentlyContinue) {'Yes'} else {'No'})"
Write-Info "Git Installed: $(if (Get-Command git -ErrorAction SilentlyContinue) {'Yes'} else {'No'})"
Write-Info "Workspace Directory: $workspaceDirectory ($(if (Test-Path -LiteralPath $workspaceDirectory) {'Exists'} else {'Missing'}))"
Write-Info "Dotfiles Repository: $dotfilesDirectory ($(if (Test-Path -LiteralPath $dotfilesDirectory) {'Cloned'} else {'Missing'}))"
Write-Info "Setup Modules Results:"
foreach ($module in $scriptResults.Keys) {
    $status = if ($scriptResults[$module] -eq 0) { "Success" } else { "Failed" }
    Write-Info " - $module : $status (Exit Code: $($scriptResults[$module]))"
}
Write-Info "Log File: $logFile"
Write-Info "========================================================"

# stop logging
Stop-Logging
