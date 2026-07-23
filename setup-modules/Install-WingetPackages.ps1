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
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw "Winget is required to install configured packages."
    }

    Write-Host "Reading package configuration from $ConfigPath..."
    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        Write-Warning "Package configuration file not found: $ConfigPath. Skipping package installation."
        exit 0
    }

    $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json

    # Determine which groups to install from bootstrap config if not passed explicitly.
    # An explicit empty INSTALL_PACKAGES array means "install no package groups", not "install all groups".
    $groupsSpecified = $PSBoundParameters.ContainsKey('Groups')
    $bootstrapHasInstallPackages = $false
    if (-not $groupsSpecified -and (Test-Path -LiteralPath $BootstrapPath)) {
        $bootstrap = Get-Content -LiteralPath $BootstrapPath -Raw | ConvertFrom-Json
        $bootstrapHasInstallPackages = $bootstrap.PSObject.Properties.Name -contains 'INSTALL_PACKAGES'
        if ($bootstrapHasInstallPackages) {
            $Groups = @($bootstrap.INSTALL_PACKAGES)
            if ($Groups.Count -eq 0) {
                Write-Host "INSTALL_PACKAGES is explicitly empty. Skipping package installation."
                exit 0
            }
            Write-Host "Using INSTALL_PACKAGES groups from bootstrap config: $($Groups -join ', ')"
        }
    }
    $installAllGroups = (-not $groupsSpecified) -and (-not $bootstrapHasInstallPackages) -and ($Groups.Count -eq 0)

    # Collect package IDs from specified groups (or all groups if none specified).
    # The 'Packages' property contains Microsoft Store IDs which require a different install path - skip them here.
    $packageIds = [System.Collections.Generic.List[string]]::new()

    foreach ($property in $config.PSObject.Properties) {
        if ($property.Name -eq 'Packages') { continue }

        $includeGroup = $installAllGroups -or ($Groups -contains $property.Name)
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
    $failedPackages = [System.Collections.Generic.List[string]]::new()

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
                Write-Warning "Failed to install package '$packageId'. Winget exited with code $LASTEXITCODE."
                $failedPackages.Add($packageId)
            } else {
                Write-Host "Successfully installed package '$packageId'."
            }
        }
    }

    if ($failedPackages.Count -gt 0) {
        throw "Winget failed to install $($failedPackages.Count) package(s): $($failedPackages -join ', ')"
    }
}
catch {
    Write-Error "An error occurred while installing Winget packages: $_"
    exit 1
}

Write-Host "Winget package installation process complete."
