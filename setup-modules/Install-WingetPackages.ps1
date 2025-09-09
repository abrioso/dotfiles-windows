<#
.SYNOPSIS
    Installs packages using Winget based on a JSON configuration file.

.DESCRIPTION
    This script reads a list of packages from 'dotfiles-configurations/winget-packages.json',
    checks if each package is already installed, and installs it if it is not.
    This script is designed to be idempotent.
#>
param (
    [string]$ConfigPath = "$PSScriptRoot/../dotfiles-configurations/winget-packages.json"
)

function Test-IsElevated {
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $p = [System.Security.Principal.WindowsPrincipal]::new($id)
    $p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

try {
    Write-Host "Reading package configuration from $ConfigPath..."
    $config = Get-Content -Path $ConfigPath | ConvertFrom-Json

    $allPackageIds = $config.PSObject.Properties | Where-Object { $_.Name -ne 'Packages' } | ForEach-Object { $_.Value }
    $uniquePackageIds = $allPackageIds | Select-Object -Unique

    Write-Host "Found $($uniquePackageIds.Count) unique packages to process."

    foreach ($packageId in $uniquePackageIds) {
        Write-Host "Processing package: $packageId"

        # Check if the package is already installed
        $installedPackage = winget list --id $packageId --source winget --accept-source-agreements

        if ($installedPackage) {
            Write-Host "Package '$packageId' is already installed. Skipping."
        } else {
            Write-Host "Package '$packageId' not found. Installing..."
            winget install --id $packageId --source winget --accept-source-agreements --accept-package-agreements

            if ($LASTEXITCODE -ne 0) {
                Write-Error "Failed to install package '$packageId'. Winget exited with code $LASTEXITCODE."
            } else {
                Write-Host "Successfully installed package '$packageId'."
            }
        }
    }
}
catch {
    Write-Error "An error occurred while installing Winget packages: $_"
    exit 1
}

Write-Host "Winget package installation process complete."
