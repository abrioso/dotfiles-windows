# Equivalent PowerShell script for 4.developer.configuration.admin.yaml
# Minimum OS version check
$minVersion = [Version]'10.0.22000'
$currentVersion = [System.Environment]::OSVersion.Version
if ($currentVersion -lt $minVersion) {
    Write-Error "Minimum OS version $minVersion required. Current: $currentVersion"
    exit 1
}

# Enable Developer Mode
# Note: This requires registry edit and may need admin rights
$regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock"
if (-not (Test-Path $regPath)) {
    New-Item -Path $regPath -Force | Out-Null
}
Set-ItemProperty -Path $regPath -Name "AllowDevelopmentWithoutDevLicense" -Value 1 -Type DWord
Write-Host "Developer Mode enabled. You may need to restart your computer."
