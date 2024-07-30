# Run from an elevated PowerShell session
# Install PowerShell
winget install Microsoft.PowerShell

# Update the system PATH variable
$env:Path += ";$([System.Environment]::GetEnvironmentVariable('Path','Machine'))"

# Run the setup script
$scriptPath = Join-Path $PSScriptRoot "setup.ps7.ps1"
pwsh.exe -File $scriptPath