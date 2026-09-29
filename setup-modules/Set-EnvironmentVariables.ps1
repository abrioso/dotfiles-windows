<#
.SYNOPSIS
    Configures system and user environment variables from a JSON file.

.DESCRIPTION
    This script reads environment variable definitions from 'dotfiles-configurations/env-variables.json'.
    It checks if each variable is already set to the correct value before applying it.
    This script is designed to be idempotent.
#>
param (
    [string]$ConfigPath = "$PSScriptRoot/../dotfiles-configurations/env-variables.json",
    [switch]$MachineOnly
)

$ErrorActionPreference = 'Stop'

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

    # Validate the whole file before applying any values.
    foreach ($entry in $variables) {
        if ([string]::IsNullOrWhiteSpace($entry.Name) -or $null -eq $entry.Value -or
            $entry.Scope -notin @('User', 'Machine')) {
            throw "Invalid environment entry: Name, Value and User/Machine Scope are required."
        }
    }
    $pendingMachineChanges = $false
    foreach ($variable in $variables) {
        if ($MachineOnly -and $variable.Scope -ne 'Machine') { continue }
        $name = $variable.Name
        $value = $variable.Value
        $scope = $variable.Scope

        $currentValue = [System.Environment]::GetEnvironmentVariable($name, $scope)
        if ($scope -eq 'Machine' -and $currentValue -ne $value -and -not (Test-IsElevated)) {
            if ($MachineOnly) { throw 'Machine environment changes require elevation.' }
            $pendingMachineChanges = $true
            continue
        }

        if ($currentValue -eq $value) {
            Write-Host "Environment variable '$name' is already set correctly in the '$scope' scope. Skipping."
        } else {
            Write-Host "Setting environment variable '$name' in the '$scope' scope..."
            [System.Environment]::SetEnvironmentVariable($name, $value, $scope)
            Write-Host "Successfully set environment variable '$name'."
        }
    }
    if ($pendingMachineChanges) {
        $resolvedConfigPath = (Resolve-Path -LiteralPath $ConfigPath).Path
        $hostPath = (Get-Process -Id $PID).Path
        $arguments = '-NoProfile -File "{0}" -ConfigPath "{1}" -MachineOnly' -f $PSCommandPath, $resolvedConfigPath
        $child = Start-Process -FilePath $hostPath -ArgumentList $arguments -Verb RunAs -Wait -PassThru -ErrorAction Stop
        if ($null -eq $child -or $child.ExitCode -ne 0) {
            throw 'Elevated machine environment configuration failed.'
        }
    }
}
catch {
    Write-Error "An error occurred while setting environment variables: $_" -ErrorAction Continue
    exit 1
}

Write-Host "Environment variable setup complete."
