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


# Install PowerShell
winget install --id Microsoft.PowerShell -e 

# Update the system PATH variable
$env:Path += ";$([System.Environment]::GetEnvironmentVariable('Path','Machine'))"

# Run the setup scripts
# 0. Install the pre-requisites
$scriptPath = Join-Path $PSScriptRoot "setup.ps7-0-prerequisites-admin.ps1"
$process = Start-Process -FilePath "pwsh.exe" -ArgumentList "-File $scriptPath" -PassThru
Wait-Process -Id $process.Id

# 1. Run the DSC configurations
$scriptPath = Join-Path $PSScriptRoot "setup.ps7-1-dsc-configs-admin.ps1"
$process = Start-Process -FilePath "pwsh.exe" -ArgumentList "-File $scriptPath" -PassThru
Wait-Process -Id $process.Id

# 2. Run the DSC configurations as a normal user
$scriptPath = Join-Path $PSScriptRoot "setup.ps7-2-dsc-configs-user.ps1"
$process = Start-Process -FilePath "pwsh.exe" -ArgumentList "-File $scriptPath" -PassThru
Wait-Process -Id $process.Id

# stop logging
Stop-Transcript