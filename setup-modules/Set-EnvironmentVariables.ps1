<#
.SYNOPSIS
    Configures system and user environment variables from a JSON file.

.DESCRIPTION
    This script reads environment variable definitions from 'dotfiles-configurations/env-variables.json'.
    It checks if each variable is already set to the correct value before applying it.
    This script is designed to be idempotent.
#>
param (
    [string]$ConfigPath = "$PSScriptRoot/../dotfiles-configurations/env-variables.json"
)

function Test-IsElevated {
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $p = [System.Security.Principal.WindowsPrincipal]::new($id)
    $p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

try {
    Write-Host "Reading environment variable configuration from $ConfigPath..."
    if (-not (Test-Path $ConfigPath)) {
        Write-Warning "Configuration file not found: $ConfigPath. Skipping environment variable setup."
        exit 0
    }

    $configContent = Get-Content -Path $ConfigPath -Raw
    if ([string]::IsNullOrWhiteSpace($configContent) -or $configContent.Trim() -eq "{}") {
        Write-Host "Configuration file is empty. No environment variables to set."
        exit 0
    }

    $config = $configContent | ConvertFrom-Json
    $variables = $config.EnvironmentVariables

    if (-not $variables) {
        Write-Host "No 'EnvironmentVariables' array found in the configuration file. Nothing to do."
        exit 0
    }

    Write-Host "Found $($variables.Count) environment variables to process."

    foreach ($variable in $variables) {
        $name = $variable.Name
        $value = $variable.Value
        $scope = $variable.Scope

        if (-not $name -or -not $value -or -not $scope) {
            Write-Warning "Skipping invalid variable entry. 'Name', 'Value', and 'Scope' are required."
            continue
        }

        if ($scope -notin @('User', 'Machine')) {
            Write-Warning "Skipping variable '$name'. Invalid scope '$scope'. Must be 'User' or 'Machine'."
            continue
        }

        if ($scope -eq 'Machine' -and -not (Test-IsElevated)) {
            Write-Warning "Skipping machine-level variable '$name' because the script is not running with Administrator privileges."
            continue
        }

        $currentValue = [System.Environment]::GetEnvironmentVariable($name, $scope)

        if ($currentValue -eq $value) {
            Write-Host "Environment variable '$name' is already set correctly in the '$scope' scope. Skipping."
        } else {
            Write-Host "Setting environment variable '$name' in the '$scope' scope..."
            [System.Environment]::SetEnvironmentVariable($name, $value, $scope)
            Write-Host "Successfully set environment variable '$name'."
        }
    }
}
catch {
    Write-Error "An error occurred while setting environment variables: $_"
    exit 1
}

Write-Host "Environment variable setup complete."
