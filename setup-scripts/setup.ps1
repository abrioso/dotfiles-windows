# Main bootstrap script. 
# Installs the pre-requisites and starts the other setup scripts with Powershell 7 

# Install PowerShell
winget install --id Microsoft.PowerShell -e 

# Update the system PATH variable
$env:Path += ";$([System.Environment]::GetEnvironmentVariable('Path','Machine'))"

# Run the setup script
$scriptPath = Join-Path $PSScriptRoot "setup.ps7.ps1"
pwsh.exe -File $scriptPath