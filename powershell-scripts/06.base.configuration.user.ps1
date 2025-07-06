# Equivalent PowerShell script for 06.base.configuration.user.dsc.yaml
# Minimum OS version check
# (No MinVersion specified, just check for OS presence)

# Create workspace directory if it doesn't exist
$workspaceDir = Join-Path $env:USERPROFILE "workspace"
if (-not (Test-Path $workspaceDir)) {
    New-Item -ItemType Directory -Path $workspaceDir | Out-Null
}

# Install Git
winget install --id git --accept-source-agreements --accept-package-agreements

# Clone dotfiles repository (uncomment to enable)
# git clone https://github.com/abrioso/dotfiles-windows $workspaceDir\dotfiles-windows


$workspacePath = "$env:USERPROFILE\workspace"
          if (-not (Test-Path $workspacePath)) {
          New-Item -ItemType Directory -Path $workspacePath | Out-Null
          }
          
