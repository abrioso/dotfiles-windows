## Description: This script installs the pre-requisites for the dotfiles setup

# Get some useful data for logging
$dateTime = Get-Date -Format "yyyyMMdd-HHmmss"
$logDir = Split-Path -Parent $PSScriptRoot
$logDir = Join-Path $logDir "logs"
$scriptName = Split-Path -Leaf $PSCommandPath
$logFile = "$logDir/$scriptName-$dateTime.txt"

# start logging
Start-Transcript -Path $logFile

# Run as a normal user
    Write-Host "Running $PSCommandPath as $env:UserName"


Write-Host "Installing the pre-requisites for the dotfiles setup"
# Install the Winget Cmdlet required for enabling Windows features and system-level installation
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
if (Get-Module -ListAvailable -Name Microsoft.WinGet.Configuration) {
    Update-Module -Name Microsoft.WinGet.Configuration
} else {
    Install-Module -Name Microsoft.WinGet.Configuration -AllowPrerelease -AcceptLicense
}

$env:Path += ";" + [System.Environment]::GetEnvironmentVariable("Path", "Machine")

$customProfileDirectory = [System.IO.Path]::Combine($env:USERPROFILE, 'PowerShell-Custom')
$profileDirectory = Split-Path -Parent $PROFILE
if (-not (Test-Path $customProfileDirectory)) {
    #create a link to $profileDirectory
    New-Item -ItemType SymbolicLink -Path $customProfileDirectory -Value $profileDirectory -Force | Out-Null
}

Write-Host "Pre-requisites installation completed"
Start-Sleep -Seconds 15

# stop logging
Stop-Transcript

# End of script