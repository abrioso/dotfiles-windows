<#
.SYNOPSIS
Script to run DSC configurations as a normal User.

.DESCRIPTION
Executes DSC configurations from YAML files in the specified folder.

.NOTES
Requires PowerShell 7 and the WinGet DSC module.
#>

Import-Module "$PSScriptRoot\setup-functions.ps1" -Force -ErrorAction Stop

# Get some useful data for logging
$dateTime = Get-Date -Format "yyyyMMdd-HHmmss"
$logDir = Split-Path -Parent $PSScriptRoot
$logDir = Join-Path $logDir "logs"
$scriptName = Split-Path -Leaf $PSCommandPath
$logFile = "$logDir/$scriptName-$dateTime.txt"

# start logging
Start-Logging -LogFilePath $logFile

# Check to see if we are running PowerShell 7 or later
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Error "This script requires PowerShell 7 or later."
    exit 1
}

# Can be run as a normal user

# Current user
$username = Get-CurrentUser

# Check to see if we are currently running "as Administrator"
if (!(Test-Elevated)) {
    Write-Host "Running $PSCommandPath as $username"
 } else {
    Write-Host "Running $PSCommandPath as Administrator"
 }

Write-Host "Installing the pre-requisites for the dotfiles setup:"
$prerequisitesInstalled = Install-DotfilesPrerequisites

if (-not $prerequisitesInstalled) {
    Write-ErrorMessage "Failed to install prerequisites. Exiting script."
    Stop-Logging
    Exit 1
} else {
    Write-Info "Prerequisites installed successfully."
}

# Update the environment PATH variable to include the system PATH
# This is necessary for the script to find the WinGet Cmdlet and other system tools
Write-Info "Refreshing PATH environment variable..."
try {
    $env:Path += ";" + [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    Write-Info "PATH environment variable refreshed successfully"
} catch {
    Write-WarningMessage "Failed to refresh PATH environment variable: $_"
}


# Set the DotFilesRoot to the directory path of the script
# This is used to locate the DSC configurations and other resources
$DotFilesRoot = Split-Path -Parent $MyInvocation.MyCommand.Path | Split-Path -Parent


# Apply the dotfiles bootstrap variables
Write-Host "Applying dotfiles bootstrap variables..."
$DotfilesVariables = Get-DotfilesBootstrapVariables
if (-not $DotfilesVariables) {
    Write-Host "No dotfiles bootstrap variables found." -ForegroundColor Yellow
    Stop-Transcript
    Exit 1
}

# Validate required configuration values
$requiredVars = @("INSTALL_PACKAGES", "INSTALL_FEATURES", "INSTALL_SETTINGS", "VM_EXCEPTIONS")
$missingVars = $requiredVars | Where-Object { -not $DotfilesVariables.$_ }

if ($missingVars) {
    Write-Host "Missing required configuration variables: $($missingVars -join ', ')" -ForegroundColor Red
    Stop-Transcript
    Exit 1
}

# Check if the machine is running in a VM environment
$isVM = Test-RunningInVM
if ($isVM) {
    Write-Host "Running in a VM environment" -ForegroundColor Yellow
} else {
    Write-Host "Not running in a VM environment"
}

# Run the DSC configuration using the Winget Cmdlet. Winget.exe cannot run as system or install Windows Optional Features
# The DSC configuration will install the required features and tools
$DscConfigFolder = Join-Path $DotFilesRoot "dsc-configurations"
if (-not (Test-Path -Path $DscConfigFolder)) {
    Write-Host "DSC configuration folder not found: $DscConfigFolder" -ForegroundColor Yellow
    # Throw an error
    throw "DSC configuration folder not found: $DscConfigFolder"
}

# Create a empty list of DSC files to be applied
$DSCFiles = @()

# for each value in $DotfilesVariables.INSTALL_FEATURE add the the file to a list of DSC files to be applied based on a filter
foreach ($feature in $DotfilesVariables.INSTALL_FEATURES) {
    # check if the feature is in the list of VM exceptions
    if ($DotfilesVariables.VM_EXCEPTIONS -contains $feature -and $isVM) {
        Write-Host "Skipping DSC Configuration for feature $feature as it is an VM_EXCEPTION on a VM host"
        continue
    }
    $DSCFiles += Get-ChildItem -Path $DscConfigFolder -Filter "*$feature*admin.dsc.yaml"
}
# for each value in $DotfilesVariables.INSTALL_PACKAGE add the the file to a list of DSC files to be applied based on a filter
foreach ($package in $DotfilesVariables.INSTALL_PACKAGES) {
    # check if the package is in the list of VM exceptions
    if ($DotfilesVariables.VM_EXCEPTIONS -contains $package -and $isVM) {
        Write-Host "Skipping DSC Configuration for package $package as it is an VM_EXCEPTION on a VM host"
        continue
    }    
    $DSCFiles += Get-ChildItem -Path $DscConfigFolder -Filter "*$package*admin.dsc.yaml"
}
# for each value in $DotfilesVariables.INSTALL_SETTINGS add the the file to a list of DSC files to be applied based on a filter
foreach ($setting in $DotfilesVariables.INSTALL_SETTINGS) {
    # check if the setting is in the list of VM exceptions
    if ($DotfilesVariables.VM_EXCEPTIONS -contains $setting -and $isVM) {
        Write-Host "Skipping DSC Configuration for setting $setting as it is an VM_EXCEPTION on a VM host"
        continue
    } 
    $DSCFiles += Get-ChildItem -Path $DscConfigFolder -Filter "*$setting*admin.dsc.yaml"
}

# Filter out any null entries and ensure uniqueness
$DSCFiles = $DSCFiles | Where-Object { $_ } | Select-Object -Unique

# Check if there are any DSC files to be applied
if ($DSCFiles.Count -eq 0) {
    Write-Host "No DSC files found to be applied" -ForegroundColor Yellow
    # Throw an error
    throw "No DSC files found to be applied"
}

# Sort the DSC files by name
$DSCFiles = $DSCFiles | Sort-Object -Property Name

# Display the list of DSC files to be applied
Write-Host "DSC Files to be applied:"
foreach ($DSCFile in $DSCFiles) {
    Write-Host $DSCFile.FullName
}

# Create a dictionary of DSC files and their results
$DSCResults = @{}


# Apply the DSC configurations
foreach ($DSCFile in $DSCFiles) {
    Write-Host "Running DSC Configuration (as Admin): $($DSCFile.FullName)"
    try {
        # Add error handling for the specific pipe error
        $DSCresult = Get-WinGetConfiguration -File $DSCFile.FullName | Invoke-WinGetConfiguration -AcceptConfigurationAgreements
        
        # Add the result to the dictionary, handling null results gracefully
        if ($DSCresult) {
            $DSCResults.Add($DSCFile.FullName, $DSCresult)
            
            if ($DSCresult.ResultCode -ne 0) {
                Write-Host "Failed to run DSC Configuration (as Admin): $($DSCFile.FullName)" -ForegroundColor Yellow
                Write-Host "Result Code: $($DSCresult.ResultCode)"
                
                $containsPipeError = $false
                foreach ($unitResult in $DSCresult.UnitResults) {
                    if ($unitResult.ResultCode -ne 0) {
                        Write-Host "Failed to run DSC Unit: $($unitResult.UnitName)"
                        Write-Host "Result Code: $($unitResult.ResultCode)"
                        Write-Host "Result Type: $($unitResult.Type)"
                        Write-Host "Result Message: $($unitResult.Message)"
                        Write-Host "Result Description: $($unitResult.Description)"
                                                
                        if ($unitResult.Description -match "The specified account name is already a member of the group" -or 
                            $unitResult.Description -match "System error 1378" -or 
                            $unitResult.Message -match "already a member") {
                            Write-Host "User already in group - continuing" -ForegroundColor Yellow
                            $containsPipeError = $true  # Treat as non-critical error
                        }
                        # Check for pipe error and handle it differently
                        if ($unitResult.Description -match "TransactNamedPipe" -or $unitResult.Message -match "TransactNamedPipe") {
                            $containsPipeError = $true
                            Write-Host "Pipe communication error detected - this usually happens with GUI applications or browsers" -ForegroundColor Yellow
                        }
                    }
                }
                
                # Only throw an error if it's not a pipe error or based on your preference
                if (-not $containsPipeError) {
                    Write-Host "Configuration failed with serious error - stopping" -ForegroundColor Red
                    Start-Sleep -Seconds 10
                    throw "DSC Configuration Failed"
                } else {
                    Write-Host "Continuing despite pipe error - this may be expected behavior" -ForegroundColor Yellow
                }
            }
        } else {
            Write-Host "Warning: DSC result was null for $($DSCFile.FullName)" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "Exception occurred processing DSC file: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Failed to run DSC Configuration (as Admin): $($DSCFile.FullName)"
        Write-Host "Error: $($_.Exception.Message)"
        
        # Check if it's a pipe error and handle it differently
        if ($_.Exception.Message -match "TransactNamedPipe") {
            Write-Host "Pipe communication error detected - continuing" -ForegroundColor Yellow
        } else {
            Start-Sleep -Seconds 10
            throw "DSC Configuration Failed"
        }
    }
}
Write-Host "DSC Configuration (as Admin) Completed"

# Write the script execution summary
Write-Host "DSC Configuration Results:"
foreach ($DSCResult in $DSCResults.GetEnumerator()) {
    Write-Host "DSC Configuration: $($DSCResult.Key)"
    Write-Host "Result Code: $($DSCResult.Value.ResultCode)"
    foreach ($unitResult in $DSCResult.Value.UnitResults) {
        Write-Host "DSC Unit: $($unitResult.UnitName)"
        Write-Host "Result Code: $($unitResult.ResultCode)"
        Write-Host "Result Type: $($unitResult.Type)"
        Write-Host "Result Message: $($unitResult.Message)"
        Write-Host "Result Description: $($unitResult.Description)"
        Write-Host "Result Details: $($unitResult.Details)"
    }
}

Write-Host "DSC Configuration (as $username) Completed"
Start-Sleep -Seconds 15

# stop logging
Stop-Transcript

# End of script