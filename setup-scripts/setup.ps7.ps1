# Run from an elevated PowerShell session
# Install the Winget Cmdlet required for enabling Windows features and system-level installation
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
Install-Module -Name Microsoft.WinGet.Configuration -AllowPrerelease -AcceptLicense

$env:Path += ";" + [System.Environment]::GetEnvironmentVariable("Path", "Machine")

# Set the value of $PSScriptRoot to the directory path of the script
$DotFilesRoot = Split-Path -Parent $MyInvocation.MyCommand.Path | Split-Path -Parent


# Run the DSC configuration using the Winget Cmdlet. Winget.exe cannot run as system or install Windows Optional Features
# The DSC configuration will install the required features and tools
$DscConfigFolder = Join-Path $DotFilesRoot "dsc-configurations"
$DSCFiles = Get-ChildItem -Path $DscConfigFolder -Filter "*.dsc.yaml"

foreach ($DSCFile in $DSCFiles) {
    Write-Host "Running DSC Configuration: $($DSCFile.FullName)"
   $DSCresult = Get-WinGetConfiguration -File $DSCFile.FullName | Invoke-WinGetConfiguration -AcceptConfigurationAgreements

    if ($DSCresult.ResultCode -ne 0) {
        Write-Host "Failed to run DSC Configuration: $($DSCFile.FullName)"
        Write-Host "Result Code: $($DSCresult.ResultCode)"
        foreach ($unitResult in $DSCresult.UnitResults) {
            if($unitResult.ResultCode -ne 0) {
                Write-Host "Failed to run DSC Unit: $($unitResult.UnitName)"
                Write-Host "Result Code: $($unitResult.ResultCode)"
                Write-Host "Result Type: $($unitResult.Type)"
                Write-Host "Result Message: $($unitResult.Message)"
                Write-Host "Result Description: $($unitResult.Description)"
#                Write-Host "Result Details: $($unitResult.Details)"
                throw "DSC Configuration Failed"
            }
        }
    }
}

Write-Host "DSC Configuration Completed"