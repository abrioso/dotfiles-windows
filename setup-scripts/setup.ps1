## Main bootstrap script. 
## Installs the pre-requisites and starts the other setup scripts with Powershell 7 

# Get some useful data for logging
$dateTime = Get-Date -Format "yyyyMMdd-HHmmss"
$logDir = Split-Path -Parent $PSScriptRoot
$logDir = Join-Path $logDir "logs"
$scriptName = Split-Path -Leaf $PSCommandPath
$logFile = "$logDir/$scriptName-$dateTime.txt"

# start logging
Start-Transcript -Path $logFile


Write-Host "Installing the pre-requisites for the dotfiles setup"

# Install PowerShell & Git
Write-Host "Installing PowerShell & Git"
winget install --id Microsoft.PowerShell -e 
winget install --id Git.Git -e

# Check if NuGet provider is installed
if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
    Write-Host "NuGet provider is not installed. Installing now..."
    Install-PackageProvider -Name NuGet -Force -Scope CurrentUser
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
    Uninstall-Module -Name Microsoft.WinGet.Configuration -AllVersions -Force
}

Write-Host "Installing the Microsoft.WinGet.Configuration module..."
Install-Module -Name Microsoft.WinGet.Configuration -AllowPrerelease -AcceptLicense -Force

# Update the system PATH variable
$env:Path += ";$([System.Environment]::GetEnvironmentVariable('Path','Machine'))"

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
    Write-Host "Please make sure that the file exists and try again"
    Exit
}

Write-Host "Dotfiles Bootstrap Variables:"
Write-Host $DotfilesVariables | Format-List

# Create a symbolic link to the custom profile directory
Write-Host "Creating a symbolic link to the custom profile directory"
$customProfileDirectory = Join-Path $env:USERPROFILE $DotfilesVariables.CUSTOM_PROFILE_FOLDER
$profileDirectory = Split-Path -Parent $PROFILE
if (-not (Test-Path $customProfileDirectory)) {
    #create a link to $profileDirectory
    New-Item -ItemType SymbolicLink -Path $customProfileDirectory -Value $profileDirectory -Force | Out-Null
}

# Create workspace directory if it does not exist
Write-Host "Creating workspace directory"
$workspaceDirectory = Join-Path $env:USERPROFILE $DotfilesVariables.WORKSPACE_FOLDER
if (-not (Test-Path $workspaceDirectory)) {
    #create the workspace directory
    New-Item -ItemType Directory -Path $workspaceDirectory -Force | Out-Null
}

# Run the setup scripts
# 0. Install the pre-requisites
#$scriptPath = Join-Path $PSScriptRoot "setup.ps7-0-prerequisites-admin.ps1"
#$process = Start-Process -FilePath "pwsh.exe" -ArgumentList "-File $scriptPath" -PassThru
#Wait-Process -Id $process.Id
#Write-Output "Process exited with code: $($process.ExitCode)"

#$scriptPath = Join-Path $PSScriptRoot "setup.ps7-0-prerequisites-user.ps1"
#$process = Start-Process -FilePath "pwsh.exe" -ArgumentList "-File $scriptPath" -PassThru
#Wait-Process -Id $process.Id
#Write-Output "Process exited with code: $($process.ExitCode)"

# 1. Run the DSC configurations
$scriptPath = Join-Path $PSScriptRoot "setup.ps7-1-dsc-configs-admin.ps1"
$process = Start-Process -FilePath "pwsh.exe" -ArgumentList "-File $scriptPath" -PassThru
Wait-Process -Id $process.Id
Write-Output "Process exited with code: $($process.ExitCode)"

# 2. Run the DSC configurations as a normal user
$scriptPath = Join-Path $PSScriptRoot "setup.ps7-2-dsc-configs-user.ps1"
$process = Start-Process -FilePath "pwsh.exe" -ArgumentList "-File $scriptPath" -PassThru
Wait-Process -Id $process.Id
Write-Output "Process exited with code: $($process.ExitCode)"

# stop logging
Stop-Transcript