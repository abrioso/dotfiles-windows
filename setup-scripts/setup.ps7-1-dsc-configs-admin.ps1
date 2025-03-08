##
# 
# Script to run DSC configurations as an Administrator
# 
##

# Get some useful data for logging
$dateTime = Get-Date -Format "yyyyMMdd-HHmmss"
$logDir = Split-Path -Parent $PSScriptRoot
$logDir = Join-Path $logDir "logs"
$scriptName = Split-Path -Leaf $PSCommandPath
$logFile = "$logDir/$scriptName-$dateTime.txt"

# Create the log directory if it doesn't exist
if (!(Test-Path -Path $logDir)) {
    New-Item -Path $logDir -ItemType Directory | Out-Null
}

# start logging
Start-Transcript -Path $logFile

# Run from an elevated PowerShell session
# Elevate this powershell script to run as an administrator
function Test-Elevated {
    $wid = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $prp = New-Object System.Security.Principal.WindowsPrincipal($wid)
    $adm = [System.Security.Principal.WindowsBuiltInRole]::Administrator
    return $prp.IsInRole($adm)
}
# Check to see if we are currently running "as Administrator"
if (!(Test-Elevated)) {
    $process = Start-Process pwsh.exe -Verb RunAs -ArgumentList "-File `"$PSCommandPath`"" -PassThru
    Wait-Process -Id $process.Id
    Write-Output "Process exited with code: $($process.ExitCode)"
    # Exit the current session
    exit
 } else {
    Write-Host "Running $PSCommandPath as Administrator"
 }

# Add the machine path to the environment path
$machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
if (-not ($env:Path -split ";" | Where-Object { $_ -eq $machinePath })) {
    $env:Path += ";$machinePath"
}

# Set the value of $DotFilesRoot to the directory path of the script
$DotFilesRoot = Split-Path -Parent $MyInvocation.MyCommand.Path | Split-Path -Parent

# Run the DSC configuration using the Winget Cmdlet. Winget.exe cannot run as system or install Windows Optional Features
# The DSC configuration will install the required features and tools
$DscConfigFolder = Join-Path $DotFilesRoot "dsc-configurations"
$DSCFiles = Get-ChildItem -Path $DscConfigFolder -Filter "*admin.dsc.yaml"

$computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem
if ($computerSystem.Model -like "*Virtual Machine*") {
    Write-Output "This machine is running inside a Hyper-V host."
} else {
    Write-Output "This machine is not running inside a Hyper-V host."
}


foreach ($DSCFile in $DSCFiles) {
    Write-Host "Running DSC Configuration (as Admin): $($DSCFile.FullName)"
   $DSCresult = Get-WinGetConfiguration -File $DSCFile.FullName | Invoke-WinGetConfiguration -AcceptConfigurationAgreements

    if ($DSCresult.ResultCode -ne 0) {
        Write-Host "Failed to run DSC Configuration (as Admin): $($DSCFile.FullName)"
        Write-Host "Result Code: $($DSCresult.ResultCode)"
        foreach ($unitResult in $DSCresult.UnitResults) {
            if($unitResult.ResultCode -ne 0) {
                Write-Host "Failed to run DSC Unit: $($unitResult.UnitName)"
                Write-Host "Result Code: $($unitResult.ResultCode)"
                Write-Host "Result Type: $($unitResult.Type)"
                Write-Host "Result Message: $($unitResult.Message)"
                Write-Host "Result Description: $($unitResult.Description)"
                Write-Host "Result Details: $($unitResult.Details)"
                Start-Sleep -Seconds 15
                throw "DSC Configuration Failed"
            }
        }
    }
}

Write-Host "DSC Configuration (as Admin) Completed"
Start-Sleep -Seconds 15

# stop logging
Stop-Transcript

# End of script