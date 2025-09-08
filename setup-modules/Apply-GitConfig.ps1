<#
.SYNOPSIS
    Applies Git global configuration settings from a JSON file.

.DESCRIPTION
    This script reads Git configuration key-value pairs from 'dotfiles-configurations/git-variables.json'.
    It checks if each Git config value is already set correctly before applying it.
    This script is designed to be idempotent.
#>
param (
    [string]$ConfigPath = "$PSScriptRoot/../dotfiles-configurations/git-variables.json"
)

try {
    Write-Host "Reading Git configuration from $ConfigPath..."
    if (-not (Test-Path $ConfigPath)) {
        Write-Warning "Configuration file not found: $ConfigPath. Skipping Git configuration."
        exit 0
    }

    $config = Get-Content -Path $ConfigPath | ConvertFrom-Json
    $properties = $config.PSObject.Properties

    if ($properties.Count -eq 0) {
        Write-Host "Git configuration file is empty. Nothing to do."
        exit 0
    }

    Write-Host "Found $($properties.Count) Git configuration settings to process."

    foreach ($property in $properties) {
        $key = $property.Name
        $desiredValue = $property.Value

        try {
            $currentValue = git config --global $key
        }
        catch {
            # git config returns a non-zero exit code if the key doesn't exist
            $currentValue = $null
        }

        if ($currentValue -eq $desiredValue) {
            Write-Host "Git config '$key' is already set to '$desiredValue'. Skipping."
        } else {
            Write-Host "Setting Git config '$key' to '$desiredValue'..."
            git config --global $key $desiredValue
            Write-Host "Successfully set Git config '$key'."
        }
    }
}
catch {
    Write-Error "An error occurred while applying Git configuration: $_"
    exit 1
}

Write-Host "Git configuration setup complete."
