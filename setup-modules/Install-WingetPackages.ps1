<#
.SYNOPSIS
    Installs packages using Winget based on a JSON configuration file.

.DESCRIPTION
    This script reads a list of packages from 'dotfiles-configurations/winget-packages.json'.
    It reads the bootstrap variables to determine which package groups to install,
    checks if each package is already installed, and installs it if it is not.
    This script is designed to be idempotent.
#>
param (
    [string]$ConfigPath = "$PSScriptRoot/../dotfiles-configurations/winget-packages.json",
    [string]$BootstrapPath = "$PSScriptRoot/../dotfiles-configurations/dotfiles-bootstrap-variables.json",
    [string[]]$Groups = @()
)

function Test-IsElevated {
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $p = [System.Security.Principal.WindowsPrincipal]::new($id)
    $p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

try {
    Write-Host "Reading package configuration from $ConfigPath..."
    if (-not (Test-Path $ConfigPath)) {
        Write-Warning "Package configuration file not found: $ConfigPath. Skipping package installation."
        exit 0
    }

    $config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json

    # Determine which groups to install from bootstrap config if not passed explicitly
    if ($Groups.Count -eq 0 -and (Test-Path $BootstrapPath)) {
        $bootstrap = Get-Content -Path $BootstrapPath -Raw | ConvertFrom-Json
        if ($bootstrap.INSTALL_PACKAGES) {
            $Groups = $bootstrap.INSTALL_PACKAGES
            Write-Host "Using INSTALL_PACKAGES groups from bootstrap config: $($Groups -join ', ')"
        }
    }

    # Collect package IDs from specified groups (or all groups if none specified).
    # The 'Packages' property contains Microsoft Store IDs which require a different install path - skip them here.
    $packageIds = [System.Collections.Generic.List[string]]::new()

    foreach ($property in $config.PSObject.Properties) {
        if ($property.Name -eq 'Packages') { continue }

        $includeGroup = ($Groups.Count -eq 0) -or ($Groups -contains $property.Name)
        if (-not $includeGroup) {
            Write-Host "Skipping group '$($property.Name)' (not in INSTALL_PACKAGES)."
            continue
        }

        foreach ($pkgId in $property.Value) {
            if (-not [string]::IsNullOrWhiteSpace($pkgId) -and -not $packageIds.Contains($pkgId)) {
                $packageIds.Add($pkgId)
            }
        }
    }

    Write-Host "Found $($packageIds.Count) unique packages to process."

    foreach ($packageId in $packageIds) {
        Write-Host "Processing package: $packageId"

        # Check if the package is already installed.
        # winget list always outputs a header, so we must match the package ID in the output text.
        $listOutput = winget list --id $packageId --exact --accept-source-agreements 2>&1 | Out-String
        $isInstalled = $listOutput -match [regex]::Escape($packageId)

        if ($isInstalled) {
            Write-Host "Package '$packageId' is already installed. Skipping."
        } else {
            Write-Host "Package '$packageId' not found. Installing..."
            winget install --id $packageId --exact --accept-source-agreements --accept-package-agreements

            if ($LASTEXITCODE -ne 0) {
                Write-Warning "Failed to install package '$packageId'. Winget exited with code $LASTEXITCODE. Continuing..."
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
