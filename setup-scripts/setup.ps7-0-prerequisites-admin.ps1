## Description: This script installs the pre-requisites for the dotfiles setup

# Get some useful data for logging
$dateTime = Get-Date -Format "yyyyMMdd-HHmmss"
$logDir = Split-Path -Parent $PSScriptRoot
$logDir = Join-Path $logDir "logs"
$scriptName = Split-Path -Leaf $PSCommandPath
$logFile = "$logDir/$scriptName-$dateTime.txt"

# start logging
Start-Transcript -Path $logFile

# Run from an elevated PowerShell session
# Elevate this powershell script to run as an administrator
function Test-Elevated {
    $wid = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $prp = New-Object System.Security.Principal.WindowsPrincipal($wid)
    $adm = [System.Security.Principal.WindowsBuiltInRole]::Administrator
    return $prp.IsInRole($adm)
}
# Check to see if we are currently running "as Administrator"
if (!(Test-Elevated)) {
    $process = Start-Process pwsh.exe -Verb RunAs -ArgumentList "-File `"$PSCommandPath`""
    Wait-Process -Id $process.Id
    Write-Output "Process exited with code: $($process.ExitCode)"
    # Exit the current session
    exit
 } else {
    Write-Host "Running $PSCommandPath as Administrator"
 }


Write-Host "Installing the pre-requisites for the dotfiles setup"
# Install the Winget Cmdlet required for enabling Windows features and system-level installation
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
if (Get-Module -ListAvailable -Name Microsoft.WinGet.Configuration) {
    Update-Module -Name Microsoft.WinGet.Configuration
} else {
    Install-Module -Name Microsoft.WinGet.Configuration -AllowPrerelease -AcceptLicense
}

$env:Path += ";" + [System.Environment]::GetEnvironmentVariable("Path", "Machine")

Write-Host "Pre-requisites installation completed"
Start-Sleep -Seconds 15

# stop logging
Stop-Transcript

# End of script