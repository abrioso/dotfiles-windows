# Equivalent PowerShell script for 07.pwsh.terminal.dsc.configuration.user.dsc.yaml
# Minimum OS version check
# (No MinVersion specified, just check for OS presence)

# Install Windows Terminal
winget install --id wterminal --accept-source-agreements --accept-package-agreements

# Install PowerShell
winget install --id Microsoft.PowerShell --accept-source-agreements --accept-package-agreements

# Install Oh My Posh
winget install --id JanDeDobbeleer.OhMyPosh --accept-source-agreements --accept-package-agreements

# Create custom PowerShell profile directory if it does not exist
$customProfileDir = Join-Path $env:USERPROFILE ".config\powershell"
if (-not (Test-Path $customProfileDir)) {
    New-Item -ItemType Directory -Path $customProfileDir | Out-Null
}
