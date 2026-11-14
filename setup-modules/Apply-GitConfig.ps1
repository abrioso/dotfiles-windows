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

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

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
        $desiredValue = [string]$property.Value

        if ([string]::IsNullOrWhiteSpace([string]$desiredValue)) {
            Write-Host "Git config '$key' has an empty value in the configuration file. Skipping."
            continue
        }

        # git config exits with 1 when the key does not exist; $currentValue will be $null in that case.
        $currentValues = @(git config --global --get-all -- $key 2>$null)
        $readExitCode = $LASTEXITCODE
        if ($readExitCode -eq 1) { $currentValues = @() }
        elseif ($readExitCode -ne 0) {
            throw "Failed to read Git config '$key' (exit code $readExitCode)."
        }

        if ($currentValues.Count -eq 1 -and [string]$currentValues[0] -ceq $desiredValue) {
            Write-Host "Git config '$key' is already set to '$desiredValue'. Skipping."
        } else {
            Write-Host "Setting Git config '$key' to '$desiredValue'..."
            git config --global --replace-all -- $key $desiredValue
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to write Git config '$key' (exit code $LASTEXITCODE)."
            }
            Write-Host "Successfully set Git config '$key'."
        }
    }
}
catch {
    Write-Error "An error occurred while applying Git configuration: $_" -ErrorAction Continue
    exit 1
}

Write-Host "Git configuration setup complete."
