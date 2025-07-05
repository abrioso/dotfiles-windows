# Equivalent PowerShell script for 0.base.packages.admin.dsc.yaml
# Minimum OS version check
$minVersion = [Version]'10.0.22000'
$currentVersion = [System.Environment]::OSVersion.Version
if ($currentVersion -lt $minVersion) {
    Write-Error "Minimum OS version $minVersion required. Current: $currentVersion"
    exit 1
}

# Install PowerShell (allow prerelease)
winget install --id Microsoft.PowerShell --source winget --accept-source-agreements --accept-package-agreements

# Install Windows Terminal
winget install --id wterminal --accept-source-agreements --accept-package-agreements

# Install gsudo
winget install --id gsudo --accept-source-agreements --accept-package-agreements
