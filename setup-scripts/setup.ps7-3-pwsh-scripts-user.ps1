<#
.SYNOPSIS
Script to run Setup Powershell Scripts as a normal User.

.DESCRIPTION
Executes Setup PowerShell Scripts files in the specified folder.

.NOTES
Requires PowerShell 7 and the WinGet DSC module.
#>

. "$PSScriptRoot\setup-functions.ps1"

# Get some useful data for logging
$dateTime = Get-Date -Format "yyyyMMdd-HHmmss"
$logDir = Split-Path -Parent $PSScriptRoot
$logDir = Join-Path $logDir "logs"
$scriptName = Split-Path -Leaf $PSCommandPath
$logFile = "$logDir/$scriptName-$dateTime.txt"

# start logging
Start-Logging -LogFilePath $logFile

# Check to see if we are running PowerShell 7 or later
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Error "This script requires PowerShell 7 or later."
    exit 1
}

# Can be run as a normal user

# Current user
$username = Get-CurrentUser

# Check to see if we are currently running "as Administrator"
if (!(Test-Elevated)) {
    Write-Host "Running $PSCommandPath as $username"
 } else {
    Write-Host "Running $PSCommandPath as Administrator"
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


# Set the DotFilesRoot to the directory path of the script
# This is used to locate the DSC configurations and other resources
$DotFilesRoot = Split-Path -Parent $MyInvocation.MyCommand.Path | Split-Path -Parent


# Apply the dotfiles bootstrap variables
Write-Host "Applying dotfiles bootstrap variables..."
$DotfilesVariables = Get-DotfilesBootstrapVariables
if (-not $DotfilesVariables) {
    Write-Host "No dotfiles bootstrap variables found." -ForegroundColor Yellow
    Stop-Logging
    Exit 1
}

# Validate required configuration values
$requiredVars = @("INSTALL_PACKAGES", "INSTALL_FEATURES", "INSTALL_SETTINGS", "VM_EXCEPTIONS")
$missingVars = $requiredVars | Where-Object { -not $DotfilesVariables.$_ }

if ($missingVars) {
    Write-Host "Missing required configuration variables: $($missingVars -join ', ')" -ForegroundColor Red
    Stop-Logging
    Exit 1
}

# Check if the machine is running in a VM environment
$isVM = Test-RunningInVM
if ($isVM) {
    Write-Host "Running in a VM environment" -ForegroundColor Yellow
} else {
    Write-Host "Not running in a VM environment"
}

# Get a list of setup Powershell Scripts to be run
$SetupScriptsFolder = Join-Path $DotFilesRoot "setup-pwsh-scripts"
if (-not (Test-Path -Path $SetupScriptsFolder)) {
    Write-Host "Setup scripts folder not found: $SetupScriptsFolder" -ForegroundColor Yellow
    # Throw an error
    throw "Setup scripts folder not found: $SetupScriptsFolder"
}

# Create a empty list of Setup PowerShell Scripts to be applied
$SetupScripts = @()

# Get all the ps1 files in the setup scripts folder
$SetupScripts += Get-ChildItem -Path $SetupScriptsFolder -Filter "*.ps1"

# Filter out any null entries and ensure uniqueness
$SetupScripts = $SetupScripts | Where-Object { $_ } | Select-Object -Unique

# Check if there are any Setup Scripts to be applied
if ($SetupScripts.Count -eq 0) {
    Write-Host "No Setup Scripts found to be applied" -ForegroundColor Yellow
    # Throw an error
    throw "No Setup Scripts found to be applied"
}

# Sort the Setup Scripts by name
$SetupScripts = $SetupScripts | Sort-Object -Property Name

# Display the list of Setup Scripts to be applied
Write-Host "Setup Scripts to be applied:"
foreach ($SetupScript in $SetupScripts) {
    Write-Host $SetupScript.FullName
}

# Create a dictionary of Setup Scripts and their results
$SetupResults = @{}


# Apply the Setup Scripts
foreach ($SetupScript in $SetupScripts) {
    Write-Host "Running Setup Script: $($SetupScript.FullName)"
    $result = Invoke-Command -ScriptBlock {
        param($scriptPath)
        try {
            . $scriptPath
            return @{
                ResultCode = 0
                UnitResults = @()
            }
        } catch {
            return @{
                ResultCode = 1
                UnitResults = @(@{
                    UnitName = $scriptPath
                    ResultCode = 1
                    Type = "Error"
                    Message = $_.Exception.Message
                    Description = "Failed to run Setup Script"
                    Details = $_.Exception.StackTrace
                })
            }
        }
    } -ArgumentList $SetupScript.FullName
    $SetupResults[$SetupScript.Name] = $result
}
Write-Host "Setup Configuration Completed"

# Write the script execution summary
Write-Host "Setup Configuration Results:"
foreach ($SetupResult in $SetupResults.GetEnumerator()) {
    Write-Host "Setup Configuration: $($SetupResult.Key)"
    Write-Host "Result Code: $($SetupResult.Value.ResultCode)"
}

Write-Host "Setup Configuration (as $username) Completed"
Start-Sleep -Seconds 5

# stop logging
Stop-Logging

# End of script