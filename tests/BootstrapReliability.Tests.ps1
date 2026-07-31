Describe 'Bootstrap reliability contracts' {
    BeforeAll {
        $script:repositoryRoot = Split-Path -Parent $PSScriptRoot
        . "$script:repositoryRoot/setup-scripts/setup-functions.ps1"
    }

    Context 'Windows Terminal configuration' {
        It 'does not contain machine-specific user paths or WSL distribution IDs' {
            $settingsPath = Join-Path $script:repositoryRoot 'windows-terminal-settings/settings.json'
            $settings = Get-Content -LiteralPath $settingsPath -Raw

            if ($settings -match '(?i)C:\\\\Users\\\\') {
                throw 'Windows Terminal settings must not contain a machine-specific user path.'
            }
            if ($settings -match '(?i)--distribution-id') {
                throw 'Windows Terminal settings must let Windows Terminal discover WSL distributions dynamically.'
            }
        }

        It 'elevates only settings that still require symbolic-link privileges' {
            $configPath = Join-Path $script:repositoryRoot 'dotfiles-configurations/setup-modules.json.example'
            $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
            $terminalModule = @($config.settings.base | Where-Object { $_.script -eq 'Install-WindowsTerminalSettings.ps1' })[0]
            $ompModule = @($config.settings.pwsh | Where-Object { $_.script -eq 'Install-OmpConfig.ps1' })[0]

            if (-not $terminalModule.requiresAdmin) {
                throw 'Windows Terminal settings must remain elevated while they use a symbolic link.'
            }
            if ($ompModule.requiresAdmin) {
                throw 'Oh My Posh theme deployment must not require elevation.'
            }
        }

        It 'installs the required Nerd Font before applying terminal settings' {
            $configPath = Join-Path $script:repositoryRoot 'dotfiles-configurations/setup-modules.json.example'
            $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
            $baseScripts = @($config.settings.base.script)
            $fontIndex = [Array]::IndexOf($baseScripts, 'Install-NerdFont.ps1')
            $terminalIndex = [Array]::IndexOf($baseScripts, 'Install-WindowsTerminalSettings.ps1')

            if ($fontIndex -lt 0 -or $terminalIndex -lt 0 -or $fontIndex -gt $terminalIndex) {
                throw 'The base settings must install the Nerd Font before Windows Terminal settings.'
            }
        }

        It 'deploys Oh My Posh themes without Administrator privileges' {
            $modulePath = Join-Path $script:repositoryRoot 'setup-modules/Install-OmpConfig.ps1'
            $module = Get-Content -LiteralPath $modulePath -Raw

            if ($module -notmatch 'ItemType HardLink' -or $module -notmatch 'Copy-Item') {
                throw 'Oh My Posh themes must use a hard link with a copy fallback.'
            }
            if ($module -match 'Test-IsElevated') {
                throw 'Oh My Posh theme deployment must not require an elevated process.'
            }
        }
    }

    Context 'Failure propagation' {
        It 'fails the package module when one or more Winget installs fail' {
            $modulePath = Join-Path $script:repositoryRoot 'setup-modules/Install-WingetPackages.ps1'
            $module = Get-Content -LiteralPath $modulePath -Raw

            if ($module -notmatch '\$failedPackages\.Add\(\$packageId\)') {
                throw 'Install-WingetPackages.ps1 must record failed package installs.'
            }
            if ($module -notmatch 'throw "Winget failed to install') {
                throw 'Install-WingetPackages.ps1 must fail after package installation errors.'
            }
        }

        It 'treats Winget as a required bootstrap prerequisite' {
            $functionsPath = Join-Path $script:repositoryRoot 'setup-scripts/setup-functions.ps1'
            $functions = Get-Content -LiteralPath $functionsPath -Raw

            if ($functions -notmatch 'Winget is required to install bootstrap prerequisites') {
                throw 'Bootstrap prerequisites must fail explicitly when Winget is unavailable.'
            }
        }

        It 'uses PowerShell error handling for Windows optional features' {
            $modulePath = Join-Path $script:repositoryRoot 'setup-modules/Configure-WindowsFeatures.ps1'
            $module = Get-Content -LiteralPath $modulePath -Raw

            if ($module -match '\$LASTEXITCODE') {
                throw 'PowerShell cmdlet failures must not be inferred from LASTEXITCODE.'
            }
            if ($module -notmatch 'Enable-WindowsOptionalFeature.+-ErrorAction Stop') {
                throw 'Enable-WindowsOptionalFeature must emit a terminating error on failure.'
            }
        }

        It 'fails when archive extraction or a configured module is unavailable' {
            $installerPath = Join-Path $script:repositoryRoot 'setup-scripts/install.ps1'
            $setupPath = Join-Path $script:repositoryRoot 'setup-scripts/setup.ps1'
            $installer = Get-Content -LiteralPath $installerPath -Raw
            $setup = Get-Content -LiteralPath $setupPath -Raw

            if ($installer -notmatch "throw `"Failed to extract") {
                throw 'Archive extraction failures must terminate the Git-free installer.'
            }
            if ($setup -match 'Module script not found:.+Skipping') {
                throw 'Missing configured modules must not be skipped.'
            }
        }

        It 'uses Winget exit codes to detect installed packages' {
            $modulePath = Join-Path $script:repositoryRoot 'setup-modules/Install-WingetPackages.ps1'
            $module = Get-Content -LiteralPath $modulePath -Raw

            if ($module -match '\$listOutput\s+-match') {
                throw 'Installed package detection must not parse Winget display text.'
            }
            if ($module -notmatch '\$isInstalled\s*=\s*\$LASTEXITCODE\s+-eq\s+0') {
                throw 'Installed package detection must use the Winget exit code.'
            }
        }
    }

    Context 'Git-free branch selection' {
        It 'passes the downloaded branch to the setup orchestrator' {
            $installerPath = Join-Path $script:repositoryRoot 'setup-scripts/install.ps1'
            $installer = Get-Content -LiteralPath $installerPath -Raw

            if ($installer -notmatch [regex]::Escape('& .\setup-scripts\setup.ps1 -BootstrapBranch $branch')) {
                throw 'The Git-free installer must keep setup on the downloaded branch.'
            }
        }

        It 'propagates non-interactive configuration through the bootstrap' {
            $installerPath = Join-Path $script:repositoryRoot 'setup-scripts/install.ps1'
            $setupPath = Join-Path $script:repositoryRoot 'setup-scripts/setup.ps1'
            $installer = Get-Content -LiteralPath $installerPath -Raw
            $setup = Get-Content -LiteralPath $setupPath -Raw

            if ($installer -notmatch '-NonInteractive:\$NonInteractive') {
                throw 'The Git-free installer must pass NonInteractive to setup.ps1.'
            }
            if ($setup -notmatch 'Get-DotfilesBootstrapVariables -NonInteractive:\$NonInteractive') {
                throw 'The setup orchestrator must pass NonInteractive to configuration initialization.'
            }
        }

        It 'relaunches Windows PowerShell callers in PowerShell 7 before Git operations' {
            $setupPath = Join-Path $script:repositoryRoot 'setup-scripts/setup.ps1'
            $setup = Get-Content -LiteralPath $setupPath -Raw
            $relaunchIndex = $setup.IndexOf('$PSVersionTable.PSEdition -ne "Core"')
            $cloneIndex = $setup.IndexOf('git clone')

            if ($relaunchIndex -lt 0 -or $cloneIndex -lt 0 -or $relaunchIndex -gt $cloneIndex) {
                throw 'Windows PowerShell must relaunch in PowerShell 7 before Git writes progress to stderr.'
            }
            if ($setup -notmatch '& \$pwshCommand\.Source @pwshArguments') {
                throw 'The setup script must execute its PowerShell 7 relaunch arguments.'
            }
        }

        It 'installs bootstrap prerequisites per-user without updating legacy PowerShellGet' {
            $functionsPath = Join-Path $script:repositoryRoot 'setup-scripts/setup-functions.ps1'
            $functions = Get-Content -LiteralPath $functionsPath -Raw

            if ($functions -notmatch "'--scope', 'user'") {
                throw 'Git and PowerShell bootstrap prerequisites must request user scope.'
            }
            if ($functions -match 'Install-Module -Name PowerShellGet') {
                throw 'Bootstrap must not update PowerShellGet in the active Windows PowerShell process.'
            }
        }

        It 'passes declarative package scopes to Winget installs' {
            $modulePath = Join-Path $script:repositoryRoot 'setup-modules/Install-WingetPackages.ps1'
            $module = Get-Content -LiteralPath $modulePath -Raw

            if ($module -notmatch '\$packageEntry\.scope') {
                throw 'Winget package objects must expose their configured scope.'
            }
            if ($module -notmatch '@\(''--scope'', \$packageScope\)') {
                throw 'Configured package scopes must be passed to Winget.'
            }
        }
    }

    Context 'Default configuration consistency' {
        It 'installs the package groups required by default settings' {
            $bootstrapPath = Join-Path $script:repositoryRoot 'dotfiles-configurations/dotfiles-bootstrap-variables.json.example'
            $modulesPath = Join-Path $script:repositoryRoot 'dotfiles-configurations/setup-modules.json.example'
            $packagesPath = Join-Path $script:repositoryRoot 'dotfiles-configurations/winget-packages.json.example'
            $bootstrap = Get-Content -LiteralPath $bootstrapPath -Raw | ConvertFrom-Json
            $modules = Get-Content -LiteralPath $modulesPath -Raw | ConvertFrom-Json
            $packages = Get-Content -LiteralPath $packagesPath -Raw | ConvertFrom-Json

            $required = Get-DotfilesRequiredPackageGroup -SetupConfig $modules -SelectedSettings $bootstrap.INSTALL_SETTINGS
            $missing = @($required | Where-Object { $bootstrap.INSTALL_PACKAGES -notcontains $_ })
            if ($missing.Count -gt 0) {
                throw "Default settings require missing package groups: $($missing -join ', ')."
            }
            if ($packages.PSObject.Properties.Name -contains 'Packages') {
                throw "The obsolete, ignored 'Packages' property must not be present."
            }
            if ($packages.pwsh -notcontains 'JanDeDobbeleer.OhMyPosh') {
                throw 'The pwsh package group must install Oh My Posh.'
            }

            $baseScopes = @{}
            foreach ($package in $packages.base) {
                if ($package -isnot [string]) {
                    $baseScopes[$package.id] = $package.scope
                }
            }
            foreach ($packageId in @('Git.Git', 'Microsoft.PowerShell', 'Microsoft.VisualStudioCode', 'Microsoft.WindowsTerminal')) {
                if ($baseScopes[$packageId] -ne 'user') {
                    throw "Base package '$packageId' must use user scope."
                }
            }
            foreach ($packageId in @('gerardog.gsudo', 'Microsoft.Edge')) {
                if ($baseScopes[$packageId] -ne 'machine') {
                    throw "Base package '$packageId' must use machine scope."
                }
            }

            foreach ($group in $packages.PSObject.Properties) {
                $actual = @($group.Value | ForEach-Object {
                    if ($_ -is [string]) { $_ } else { $_.id }
                })
                $sorted = @($actual | Sort-Object)
                if (($actual -join '|') -ne ($sorted -join '|')) {
                    throw "Package group '$($group.Name)' must remain sorted."
                }
            }
        }
    }
}
