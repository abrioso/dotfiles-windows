<#
.SYNOPSIS
Script to run DSC configurations as an Administrator.

.DESCRIPTION
Elevates itself to run with administrative privileges and executes DSC configurations
from YAML files in the specified folder.

.NOTES
Requires PowerShell 7 and the WinGet DSC module.
#>


# Function to elevate this powershell script to be run as an administrator
function Test-Elevated {
    $wid = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $prp = New-Object System.Security.Principal.WindowsPrincipal($wid)
    $adm = [System.Security.Principal.WindowsBuiltInRole]::Administrator
    return $prp.IsInRole($adm)
}

# Variables for logging
$dateTime = Get-Date -Format "yyyyMMdd-HHmmss"
$logDir = Split-Path -Parent $PSScriptRoot
$logDir = Join-Path $logDir "logs"
$scriptName = Split-Path -Leaf $PSCommandPath
$logFile = "$logDir/$scriptName-$dateTime.txt"

# Create the log directory if it doesn't exist
if (!(Test-Path -Path $logDir)) {
    try {
        New-Item -Path $logDir -ItemType Directory | Out-Null
    }
    catch {
        Write-Warning "Cannot create log directory: $($_.Exception.Message)"
        $logFile = "$env:TEMP\$scriptName-$dateTime.txt"
        Write-Warning "Logging to temporary location: $logFile"
    }
}

# Start logging
try {
    Start-Transcript -Path $logFile -ErrorAction Stop
}
catch {
    Write-Warning "Cannot start transcript: $($_.Exception.Message)"
}

# Check to see if we are running PowerShell 7 or later
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Error "This script requires PowerShell 7 or later."
    exit 1
}

# Check to see if we are currently running "as Administrator"
if (!(Test-Elevated)) {
    $process = Start-Process pwsh.exe -Verb RunAs -ArgumentList "-File `"$PSCommandPath`"" -PassThru
    Wait-Process -Id $process.Id
    if ($process.ExitCode -ne 0) {
        Write-Error "Process exited with code: $($process.ExitCode)"
        exit $process.ExitCode
    }
    Write-Host "Process exited with code: $($process.ExitCode)"
    # Exit the current session
    exit
 } else {
    Write-Host "Running $PSCommandPath as Administrator"
 }

# Add the machine path to the environment path
$machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
$machinePathEntries = $machinePath -split ";"
$currentPathEntries = $env:Path -split ";"
foreach ($entry in $machinePathEntries) {
    if ($entry -and -not ($currentPathEntries -contains $entry)) {
        $env:Path += ";$entry"
    }
}

# Set the value of $DotFilesRoot to the directory path of the script
$DotFilesRoot = Split-Path -Parent $MyInvocation.MyCommand.Path | Split-Path -Parent

# Run the DSC configuration using the Winget Cmdlet. Winget.exe cannot run as system or install Windows Optional Features
# The DSC configuration will install the required features and tools
$DscConfigFolder = Join-Path $DotFilesRoot "dsc-configurations"
if (-not (Test-Path -Path $DscConfigFolder)) {
    Write-Host "DSC configuration folder not found: $DscConfigFolder" -ForegroundColor Yellow
    # Throw an error
    throw "DSC configuration folder not found: $DscConfigFolder"
}

$DSCFiles = Get-ChildItem -Path $DscConfigFolder -Filter "*admin.dsc.yaml"

$computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem

# Check if the machine is running inside a Hyper-V host
if ($computerSystem.Model -like "*Virtual Machine*") {
    Write-Host "This machine is running inside a Hyper-V host."
    $isVM = $true
} else {
    Write-Host "This machine is not running inside a Hyper-V host."
    $isVM = $false
}

foreach ($DSCFile in $DSCFiles) {
    Write-Host "Running DSC Configuration (as Admin): $($DSCFile.FullName)"
    try {
        if ($DSCFile.Name -like "*hyperv*"-and $isVM) {
            Write-Host "Skipping DSC Configuration for Hyper-V host"
            continue
        }
        
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
                    Start-Sleep -Seconds 10
                    throw "DSC Configuration Failed"
                }
            }
        }
    } catch {
        Write-Host "Exception occurred processing DSC file: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Failed to run DSC Configuration (as Admin): $($DSCFile.FullName)"
        Write-Host "Error: $($_.Exception.Message)"
        Start-Sleep -Seconds 10
        throw "DSC Configuration Failed"
    }
}

Write-Host "DSC Configuration (as Admin) Completed"
Start-Sleep -Seconds 10

# stop logging
Stop-Transcript

# End of script