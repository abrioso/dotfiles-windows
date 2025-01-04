# Main bootstrap script. 
# Installs the pre-requisites and starts the other setup scripts with Powershell 7 

# Install PowerShell
winget install --id Microsoft.PowerShell -e 

# Update the system PATH variable
$env:Path += ";$([System.Environment]::GetEnvironmentVariable('Path','Machine'))"

# Run the setup scripts
# 0. Install the pre-requisites
$scriptPath = Join-Path $PSScriptRoot "setup.ps7-0-prerequisites-admin.ps1"
pwsh.exe -File $scriptPath

# 1. Run the DSC configurations
$scriptPath = Join-Path $PSScriptRoot "setup.ps7-1-dsc-configs-admin.ps1"
pwsh.exe -File $scriptPath

# 2. Run the DSC configurations as a normal user
$scriptPath = Join-Path $PSScriptRoot "setup.ps7-2-dsc-configs-user.ps1"
pwsh.exe -File $scriptPath