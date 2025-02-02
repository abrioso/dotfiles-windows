## This script reads the env-variables.json file and sets the environment variables in the user profile

# Get the directory path of the script
$DotFilesRoot = Split-Path -Parent $MyInvocation.MyCommand.Path | Split-Path -Parent

# Get the directory path of the config files
$DotFilesConfigFolder = Join-Path $DotFilesRoot "dotfiles-configurations"
$EnvFiles = Get-ChildItem -Path $DotFilesConfigFolder -Filter "env-variables.json"

# For each config file, set the environment variables
foreach ($EnvFile in $EnvFiles) {
    Write-Host "Setting Environment Variables: $($EnvFile.FullName)"
    
    # read the config file
    $EnvConfig = Get-Content -Path $EnvFile.FullName | ConvertFrom-Json
    # for each config variable, set the environment variable
    foreach ($EnvVariable in $EnvConfig.PSObject.Properties) {
        Write-Host "Setting Environment Variable: $($EnvVariable.Name) to $($EnvVariable.Value)"
        [System.Environment]::SetEnvironmentVariable($EnvVariable.Name, $EnvVariable.Value, [System.EnvironmentVariableTarget]::User)
    }
}
