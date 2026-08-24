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

    # Collect package specifications from selected groups. String entries remain supported
    # for local configuration compatibility; object entries can constrain scope and installer type.
    $packageSpecs = [System.Collections.Generic.List[object]]::new()
    $seenPackages = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($property in $config.PSObject.Properties) {
        $includeGroup = $installAllGroups -or ($Groups -contains $property.Name)
        if (-not $includeGroup) {
            Write-Host "Skipping group '$($property.Name)' (not in INSTALL_PACKAGES)."
            continue
        }

        foreach ($packageEntry in $property.Value) {
            $packageId = if ($packageEntry -is [string]) { $packageEntry } else { [string]$packageEntry.id }
            $packageScope = if ($packageEntry -is [string]) { $null } else { [string]$packageEntry.scope }
            $packageInstallerType = if ($packageEntry -is [string]) { $null } else { [string]$packageEntry.installerType }

            if ([string]::IsNullOrWhiteSpace($packageScope)) { $packageScope = $null }
            if ([string]::IsNullOrWhiteSpace($packageInstallerType)) { $packageInstallerType = $null }

            if (-not [string]::IsNullOrWhiteSpace($packageScope) -and $packageScope -notin @('user', 'machine')) {
                throw "Package '$packageId' has unsupported scope '$packageScope'. Expected 'user' or 'machine'."
            }
            if ($packageInstallerType -and $packageInstallerType -notin @('wix')) {
                throw "Package '$packageId' has unsupported installer type '$packageInstallerType'. Expected 'wix'."
            }

            if ([string]::IsNullOrWhiteSpace($packageId)) {
                continue
            }

            if ($seenPackages.ContainsKey($packageId)) {
                $existingMetadata = $seenPackages[$packageId]
                if ($existingMetadata.Scope -ne $packageScope -or $existingMetadata.InstallerType -ne $packageInstallerType) {
                    throw "Package '$packageId' is declared with conflicting scope or installer-type metadata. Resolve the conflict before re-running."
                }
                continue
            }

            $packageSpec = [pscustomobject]@{
                Id = $packageId
                Scope = $packageScope
                InstallerType = $packageInstallerType
            }
            $seenPackages[$packageId] = $packageSpec
            $packageSpecs.Add($packageSpec)
        }
    }

    Write-Host "Found $($packageSpecs.Count) unique packages to process."
    $failedPackages = [System.Collections.Generic.List[string]]::new()

    foreach ($packageSpec in $packageSpecs) {
        $packageId = $packageSpec.Id
        $packageScope = $packageSpec.Scope
        $packageInstallerType = $packageSpec.InstallerType
        Write-Host "Processing package: $packageId"

        # Winget returns a non-zero exit code when no exact installed package is found.
        & winget list --id $packageId --exact --source winget --accept-source-agreements --disable-interactivity | Out-Null
        $isInstalled = $LASTEXITCODE -eq 0

        if ($isInstalled) {
            Write-Host "Package '$packageId' is already installed. Skipping."
        } else {
            $scopeDescription = if ($packageScope) { " with '$packageScope' scope" } else { '' }
            $installerTypeDescription = if ($packageInstallerType) { " using '$packageInstallerType' installer type" } else { '' }
            Write-Host "Package '$packageId' not found. Installing${scopeDescription}${installerTypeDescription}..."
            $installArguments = @(
                'install', '--id', $packageId, '--exact',
                '--source', 'winget',
                '--accept-source-agreements', '--accept-package-agreements', '--disable-interactivity'
            )
            if ($packageScope) {
                $installArguments += @('--scope', $packageScope)
            }
            if ($packageInstallerType) {
                $installArguments += @('--installer-type', $packageInstallerType)
            }
            & winget @installArguments

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
