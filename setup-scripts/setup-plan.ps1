<#
.SYNOPSIS
Read-only helpers for previewing local setup declarations. Does not inspect installed state.
#>

function Get-DotfilesSetupPreview {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [string]$BootstrapBranch
    )

    $configDirectory = Join-Path $RepositoryRoot 'dotfiles-configurations'
    $bootstrapPath = Join-Path $configDirectory 'dotfiles-bootstrap-variables.json'
    $variables = Read-DotfilesConfigurationObject -Path $bootstrapPath
    # Apply validates saved choices before considering the invocation's branch override.
    Assert-DotfilesSetupConfiguration -DotfilesVariables $variables -ConfigDirectory $configDirectory `
        -ModuleDirectory (Join-Path $RepositoryRoot 'setup-modules')
    if (-not [string]::IsNullOrWhiteSpace($BootstrapBranch)) {
        $variables | Add-Member -MemberType NoteProperty -Name GITHUB_DOTFILES_BRANCH -Value $BootstrapBranch -Force
    }

    $catalog = Read-DotfilesConfigurationObject (Join-Path $configDirectory 'setup-modules.json')
    $packages = Read-DotfilesConfigurationObject (Join-Path $configDirectory 'winget-packages.json')
    $features = Read-DotfilesConfigurationObject (Join-Path $configDirectory 'windows-features.json')
    $selections = [ordered]@{}
    foreach ($selection in @(
        @{ Name = 'Features'; Selector = 'INSTALL_FEATURES'; Available = @($features.PSObject.Properties.Name) },
        @{ Name = 'Capabilities'; Selector = 'INSTALL_CAPABILITIES'; Available = @() },
        @{ Name = 'Packages'; Selector = 'INSTALL_PACKAGES'; Available = @($packages.PSObject.Properties.Name) },
        @{ Name = 'Settings'; Selector = 'INSTALL_SETTINGS'; Available = @($catalog.settings.PSObject.Properties.Name) }
    )) {
        $selections[$selection.Name] = @(if (Test-DotfilesObjectProperty $variables $selection.Selector) {
            ConvertTo-DotfilesStringArray $variables.($selection.Selector)
        } else { $selection.Available })
    }

    $packageList = [System.Collections.Generic.List[object]]::new()
    $seenIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($group in $packages.PSObject.Properties) {
        if ($selections.Packages -notcontains $group.Name) { continue }
        foreach ($entry in $group.Value) {
            $id = if ($entry -is [string]) { $entry } else { $entry.id }
            if (-not $seenIds.Add($id)) { continue }
            $scope = if ($entry -is [string] -or [string]::IsNullOrWhiteSpace($entry.scope)) { $null } else { $entry.scope }
            $installerType = if ($entry -is [string] -or [string]::IsNullOrWhiteSpace($entry.installerType)) { $null } else { $entry.installerType }
            $packageList.Add([pscustomobject]@{ Id = $id; Scope = $scope; InstallerType = $installerType })
        }
    }

    $environment = Read-DotfilesConfigurationObject (Join-Path $configDirectory 'env-variables.json')
    $modules = [System.Collections.Generic.List[object]]::new()
    foreach ($module in @(Get-DotfilesSetupPlan -DotfilesVariables $variables -ConfigDirectory $configDirectory)) {
        $elevation = if ($module.RequiresAdmin) { 'Possible: catalog requires administrator; runtime may skip satisfied state.' } else { 'Not declared by catalog.' }
        if ($module.Script -eq 'Install-WingetPackages.ps1') {
            $elevation = 'Possible: machine-scope packages or installer requirements.'
        } elseif ($module.Script -eq 'Set-EnvironmentVariables.ps1') {
            $machineEntries = @($environment.PSObject.Properties | Where-Object { $_.Value.Scope -eq 'Machine' })
            if ($machineEntries.Count -gt 0) { $elevation = 'Possible: pending Machine environment changes.' }
        }
        $modules.Add([pscustomobject]@{
            Order = $modules.Count + 1
            Script = $module.Script
            RequiresAdmin = $module.RequiresAdmin
            Elevation = $elevation
            MayRequireRestart = $module.Script -in @('Configure-WindowsFeatures.ps1', 'Configure-WindowsCapabilities.ps1', 'Install-WingetPackages.ps1')
        })
    }

    # Do not include personal Git/environment values, workspace paths or repository URLs.
    [pscustomobject]@{
        SchemaVersion = 1
        Source = 'Existing local configuration in the invoked checkout; no repository refresh or persistent-clone reload.'
        Branch = $variables.GITHUB_DOTFILES_BRANCH
        Limitations = @(
            'Declarations only: installed state and OS/package availability are not checked.',
            'Apply installs/reuses PowerShell 7 and Git prerequisites, prepares the workspace clone and reloads its configuration before modules.',
            'Existing persistent configuration or a repository update can change the apply plan. Run -Plan from that clone for its local choices.',
            'Elevation and restart depend on runtime state and installers; custom modules may have additional requirements.'
        )
        Selections = [pscustomobject]$selections
        Features = @(Resolve-DotfilesWindowsFeature -ConfigPath (Join-Path $configDirectory 'windows-features.json') `
            -Groups $selections.Features -GroupsSpecified)
        Capabilities = @(Resolve-DotfilesWindowsCapability -ConfigPath (Join-Path $configDirectory 'windows-capabilities.json') `
            -Groups $selections.Capabilities -GroupsSpecified)
        Packages = $packageList.ToArray()
        Modules = $modules.ToArray()
    }
}

function Write-DotfilesSetupPreview {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Preview)

    Write-Host 'SETUP PLAN (read-only)'
    Write-Host $Preview.Source
    Write-Host "Bootstrap branch: $($Preview.Branch)"
    foreach ($selection in $Preview.Selections.PSObject.Properties) {
        Write-Host "$($selection.Name) groups: $($selection.Value -join ', ')"
    }
    Write-Host "Windows features: $($Preview.Features -join ', ')"
    Write-Host "Windows capabilities: $($Preview.Capabilities -join ', ')"
    Write-Host 'Packages (catalog order, unique IDs):'
    foreach ($package in $Preview.Packages) {
        Write-Host " - $($package.Id) [scope=$($package.Scope); installerType=$($package.InstallerType)]"
    }
    Write-Host 'Modules (execution order):'
    foreach ($module in $Preview.Modules) {
        Write-Host " $($module.Order). $($module.Script) [possible restart=$($module.MayRequireRestart)]"
        Write-Host "    Elevation: $($module.Elevation)"
    }
    foreach ($limitation in $Preview.Limitations) { Write-Host "Note: $limitation" }
}
