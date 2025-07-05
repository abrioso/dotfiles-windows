# Equivalent PowerShell script for 10.productivitytools.packages.user.dsc.yaml
# Minimum OS version check
# (No MinVersion specified, just check for OS presence)

# Install Microsoft Edge
winget install --id Microsoft.Edge --accept-source-agreements --accept-package-agreements

# Install Microsoft Office 365
winget install --id Microsoft.Office --accept-source-agreements --accept-package-agreements

# Install Microsoft Teams
winget install --id Microsoft.Teams --accept-source-agreements --accept-package-agreements

# Install Microsoft OneDrive
winget install --id Microsoft.OneDrive --accept-source-agreements --accept-package-agreements

# Install Microsoft Power BI
winget install --id Microsoft.PowerBI --accept-source-agreements --accept-package-agreements
