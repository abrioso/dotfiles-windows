## This script reads the winget-packages.json file and installs the packages using winget

# Get the directory path of the script
$DotFilesRoot = Split-Path -Parent $MyInvocation.MyCommand.Path | Split-Path -Parent

# Get the directory path of the config files
$DotFilesConfigFolder = Join-Path $DotFilesRoot "dotfiles-configurations"
$WingetFiles = Get-ChildItem -Path $DotFilesConfigFolder -Filter "*winget-packages.json"

# For each config file, set the environment variables
foreach ($WingetFile in $WingetFiles) {
    Write-Host "Setting Environment Variables: $($WingetFile.FullName)"
    
    # read the config file
    $WingetConfig = Get-Content -Path $WingetFile.FullName | ConvertFrom-Json
    # for each Package, install the package
    foreach ($Package in $WingetConfig.Packages) {
        Write-Host "Installing Package: $($Package)"
        winget install --id $Package
    }
}




