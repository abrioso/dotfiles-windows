# Run from an elevated PowerShell session
# Install the Winget Cmdlet required for enabling Windows features and system-level installation
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
Install-Module -Name Microsoft.WinGet.Configuration -AllowPrerelease -AcceptLicense

$env:Path += ";" + [System.Environment]::GetEnvironmentVariable("Path", "Machine")

# Run the DSC configuration using the Winget Cmdlet. Winget.exe cannot run as system or install Windows Optional Features
Get-WinGetConfiguration -File "$PSScriptRoot\dsc-configurations\base.configuration.dsc.yaml" | Invoke-WinGetConfiguration -AcceptConfigurationAgreements
