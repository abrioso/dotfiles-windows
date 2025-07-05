# Equivalent PowerShell script for 08.developer.packages.user.dsc.yaml
# Minimum OS version check
# (No MinVersion specified, just check for OS presence)

# Install PowerShell
winget install --id Microsoft.PowerShell --accept-source-agreements --accept-package-agreements

# Install Windows Terminal
winget install --id wterminal --accept-source-agreements --accept-package-agreements

# Install Git
winget install --id git --accept-source-agreements --accept-package-agreements

# Install GitHub CLI
winget install --id GitHub.cli --accept-source-agreements --accept-package-agreements
