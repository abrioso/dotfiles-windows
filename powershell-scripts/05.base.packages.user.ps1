# Equivalent PowerShell script for 05.base.packages.user.dsc.yaml
# Minimum OS version check
# (No MinVersion specified, just check for OS presence)

# Install PowerShell (no id specified, fallback to default)
winget install --id Microsoft.PowerShell --accept-source-agreements --accept-package-agreements

# Install Windows Terminal
winget install --id Microsoft.WindowsTerminal --accept-source-agreements --accept-package-agreements

# Install Git
winget install --id Git.Git --accept-source-agreements --accept-package-agreements

# Install Visual Studio Code
winget install --id Microsoft.VisualStudioCode --accept-source-agreements --accept-package-agreements

# Install Edge
winget install --id Microsoft.Edge --accept-source-agreements --accept-package-agreements
