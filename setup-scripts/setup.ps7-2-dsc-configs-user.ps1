# Can be run as a normal user

# Elevate this powershell script to run as an administrator
function Test-Elevated {
    $wid = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $prp = New-Object System.Security.Principal.WindowsPrincipal($wid)
    $adm = [System.Security.Principal.WindowsBuiltInRole]::Administrator
    return $prp.IsInRole($adm)
}
# Current user
$username = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name


# Check to see if we are currently running "as Administrator"
if (!(Test-Elevated)) {
    Write-Host "Running $PSCommandPath as $username"
 } else {
    Write-Host "Running $PSCommandPath as Administrator"
 }

$env:Path += ";" + [System.Environment]::GetEnvironmentVariable("Path", "Machine")

# Set the value of $PSScriptRoot to the directory path of the script
$DotFilesRoot = Split-Path -Parent $MyInvocation.MyCommand.Path | Split-Path -Parent

# Run the DSC configuration using the Winget Cmdlet. Winget.exe cannot run as system or install Windows Optional Features
# The DSC configuration will install the required features and tools
$DscConfigFolder = Join-Path $DotFilesRoot "dsc-configurations"
$DSCFiles = Get-ChildItem -Path $DscConfigFolder -Filter "*user.dsc.yaml"

foreach ($DSCFile in $DSCFiles) {
    Write-Host "Running DSC Configuration (as $username): $($DSCFile.FullName)"
   $DSCresult = Get-WinGetConfiguration -File $DSCFile.FullName | Invoke-WinGetConfiguration -AcceptConfigurationAgreements

    if ($DSCresult.ResultCode -ne 0) {
        Write-Host "Failed to run DSC Configuration (as $username): $($DSCFile.FullName)"
        Write-Host "Result Code: $($DSCresult.ResultCode)"
        foreach ($unitResult in $DSCresult.UnitResults) {
            if($unitResult.ResultCode -ne 0) {
                Write-Host "Failed to run DSC Unit: $($unitResult.UnitName)"
                Write-Host "Result Code: $($unitResult.ResultCode)"
                Write-Host "Result Type: $($unitResult.Type)"
                Write-Host "Result Message: $($unitResult.Message)"
                Write-Host "Result Description: $($unitResult.Description)"
#                Write-Host "Result Details: $($unitResult.Details)"
                Start-Sleep -Seconds 15
                throw "DSC Configuration Failed"
            }
        }
    }
}

Write-Host "DSC Configuration (as $username) Completed"
Start-Sleep -Seconds 15
# End of script