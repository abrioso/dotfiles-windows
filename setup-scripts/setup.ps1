## Main bootstrap script. 
## Installs the pre-requisites and starts the other setup scripts with Powershell 7 

# Get some useful data for logging
$dateTime = Get-Date -Format "yyyyMMdd-HHmmss"
$logDir = Split-Path -Parent $PSScriptRoot
$logDir = Join-Path $logDir "logs"
$scriptName = Split-Path -Leaf $PSCommandPath
$logFile = "$logDir/$scriptName-$dateTime.txt"

# start logging
Start-Transcript -Path $logFile


Write-Host "Installing the pre-requisites for the dotfiles setup"

# Install PowerShell & Git
Write-Host "Installing PowerShell & Git"
winget install --id Microsoft.PowerShell -e 
winget install --id Git.Git -e

# Install the Winget Cmdlet required for enabling Windows features and system-level installation
Write-Host "Installing the Winget Cmdlet"
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
if (Get-Module -ListAvailable -Name Microsoft.WinGet.Configuration) {
    Update-Module -Name Microsoft.WinGet.Configuration
} else {
    Install-Module -Name Microsoft.WinGet.Configuration -AllowPrerelease -AcceptLicense
}

# Update the system PATH variable
$env:Path += ";$([System.Environment]::GetEnvironmentVariable('Path','Machine'))"

# Create a symbolic link to the custom profile directory
Write-Host "Creating a symbolic link to the custom profile directory"
$customProfileDirectory = [System.IO.Path]::Combine($env:USERPROFILE, 'PowerShell-Custom')
$profileDirectory = Split-Path -Parent $PROFILE
if (-not (Test-Path $customProfileDirectory)) {
    #create a link to $profileDirectory
    New-Item -ItemType SymbolicLink -Path $customProfileDirectory -Value $profileDirectory -Force | Out-Null
}

## Apply the dotfiles bootstrap variables
# Get the directory path of the script
$DotfilesRoot = Split-Path -Parent $MyInvocation.MyCommand.Path | Split-Path -Parent

# Get the directory path of the config files
$DotfilesConfigFolder = Join-Path $DotfilesRoot "dotfiles-configurations"
$DotfilesVariablesFiles = Get-ChildItem -Path $DotfilesConfigFolder -Filter "dotfiles-bootstrap-variables.json"

# For each config file, set the environment variables
foreach ($DotfilesVariablesFile in $DotfilesVariablesFiles) {
    Write-Host "Setting Dotfiles Bootstrap Variables from $($DotfilesVariablesFile.FullName)"
    
    # read the config file
    $DotfilesVariables = Get-Content -Path $DotfilesVariablesFile.FullName | ConvertFrom-Json
    # for each config variable, set the environment variable
    foreach ($DotfilesVariable in $DotfilesVariables.PSObject.Properties) {
        Write-Host "Setting Dotfiles Bootstrap Variable: $($DotfilesVariable.Name) to $($DotfilesVariable.Value)"
        [System.Environment]::SetEnvironmentVariable($DotfilesVariable.Name, $DotfilesVariable.Value, [System.EnvironmentVariableTarget]::User)
    }
}

# Print the environment variables
Write-Host "Environment Variables:"
Get-ChildItem Env: | Format-Table -AutoSize

# Create workspace directory if it does not exist
Write-Host "Creating workspace directory"
$workspaceDirectory = [System.IO.Path]::Combine($env:USERPROFILE, $env:WORKSPACE_FOLDER)
if (-not (Test-Path $workspaceDirectory)) {
    #create a link to $profileDirectory
    New-Item -ItemType Directory -Path $workspaceDirectory -Force | Out-Null
}

# Run the setup scripts
# 0. Install the pre-requisites
#$scriptPath = Join-Path $PSScriptRoot "setup.ps7-0-prerequisites-admin.ps1"
#$process = Start-Process -FilePath "pwsh.exe" -ArgumentList "-File $scriptPath" -PassThru
#Wait-Process -Id $process.Id
#Write-Output "Process exited with code: $($process.ExitCode)"

#$scriptPath = Join-Path $PSScriptRoot "setup.ps7-0-prerequisites-user.ps1"
#$process = Start-Process -FilePath "pwsh.exe" -ArgumentList "-File $scriptPath" -PassThru
#Wait-Process -Id $process.Id
#Write-Output "Process exited with code: $($process.ExitCode)"

# 1. Run the DSC configurations
$scriptPath = Join-Path $PSScriptRoot "setup.ps7-1-dsc-configs-admin.ps1"
$process = Start-Process -FilePath "pwsh.exe" -ArgumentList "-File $scriptPath" -PassThru
Wait-Process -Id $process.Id
Write-Output "Process exited with code: $($process.ExitCode)"

# 2. Run the DSC configurations as a normal user
$scriptPath = Join-Path $PSScriptRoot "setup.ps7-2-dsc-configs-user.ps1"
$process = Start-Process -FilePath "pwsh.exe" -ArgumentList "-File $scriptPath" -PassThru
Wait-Process -Id $process.Id
Write-Output "Process exited with code: $($process.ExitCode)"

# stop logging
Stop-Transcript