<#
.SYNOPSIS
Script to run DSC configurations as a normal User.

.DESCRIPTION
Executes DSC configurations from YAML files in the specified folder.

.NOTES
Requires PowerShell 7 and the WinGet DSC module.
#>

Import-Module "$PSScriptRoot\setup-functions.ps1" -Force -ErrorAction Stop

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
    Stop-Transcript
    Exit 1
}

# Validate required configuration values
$requiredVars = @("INSTALL_PACKAGES", "INSTALL_FEATURES", "INSTALL_SETTINGS", "VM_EXCEPTIONS")
$missingVars = $requiredVars | Where-Object { -not $DotfilesVariables.$_ }

if ($missingVars) {
    Write-Host "Missing required configuration variables: $($missingVars -join ', ')" -ForegroundColor Red
    Stop-Transcript
    Exit 1
}

# Check if the machine is running in a VM environment
$isVM = Test-RunningInVM
if ($isVM) {
    Write-Host "Running in a VM environment" -ForegroundColor Yellow
} else {
    Write-Host "Not running in a VM environment"
}

# Run the DSC configuration using the Winget Cmdlet. Winget.exe cannot run as system or install Windows Optional Features
# The DSC configuration will install the required features and tools
$DscConfigFolder = Join-Path $DotFilesRoot "dsc-configurations"
if (-not (Test-Path -Path $DscConfigFolder)) {
    Write-Host "DSC configuration folder not found: $DscConfigFolder" -ForegroundColor Yellow
    # Throw an error
    throw "DSC configuration folder not found: $DscConfigFolder"
}

# Create a empty list of DSC files to be applied
$DSCFiles = @()

# Get all the DSC files that match the patterns in the dotfiles variables


$DSCFiles = Get-ChildItem -Path $DscConfigFolder -Filter "*user.dsc.yaml"

foreach ($DSCFile in $DSCFiles) {
    Write-Host "Running DSC Configuration (as $username): $($DSCFile.FullName)"
   $DSCresult = Get-WinGetConfiguration -File $DSCFile.FullName | Invoke-WinGetConfiguration -AcceptConfigurationAgreements

    if ($DSCresult.ResultCode -ne 0) {
        Write-Host "Failed to run DSC Configuration (as $username): $($DSCFile.FullName)"
        Write-Host "Result Code: $($DSCresult.ResultCode)"
        foreach ($unitResult in $DSCresult.UnitResults) {
            if($unitResult.ResultCode -ne 0) {
                Write-Host "Failed to run DSC Unit: $($unitResult.UnitName)"
                Write-Host "Result Code: $($unitResult.ResultCode)"
                Write-Host "Result Type: $($unitResult.Type)"
                Write-Host "Result Message: $($unitResult.Message)"
                Write-Host "Result Description: $($unitResult.Description)"
#                Write-Host "Result Details: $($unitResult.Details)"
                Start-Sleep -Seconds 15
                throw "DSC Configuration Failed"
            }
        }
    }
}

Write-Host "DSC Configuration (as $username) Completed"
Start-Sleep -Seconds 15

# stop logging
Stop-Transcript

# End of script