# Equivalent PowerShell script for 11.internetbrowser.packages.user.dsc.yaml
# Minimum OS version check
$minVersion = [Version]'10.0.22000'
$currentVersion = [System.Environment]::OSVersion.Version
if ($currentVersion -lt $minVersion) {
    Write-Error "Minimum OS version $minVersion required. Current: $currentVersion"
    exit 1
}

# Install Microsoft Edge
winget install --id Microsoft.Edge --accept-source-agreements --accept-package-agreements

# Install Google Chrome
winget install --id Google.Chrome --accept-source-agreements --accept-package-agreements

# Install Mozilla Firefox
winget install --id Mozilla.Firefox --accept-source-agreements --accept-package-agreements
