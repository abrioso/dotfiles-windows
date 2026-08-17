Describe 'Setup configuration resolution' {
    BeforeAll {
        . "$PSScriptRoot/../setup-scripts/setup-functions.ps1"

        function Get-TestConfigDirectory {
            $path = Join-Path $env:TEMP ([System.Guid]::NewGuid())
            New-Item -ItemType Directory -Path $path | Out-Null
            return $path
        }

        function Write-TestJson {
            param(
                [Parameter(Mandatory)][string]$Path,
                [Parameter(Mandatory)][string]$Json
            )

            Set-Content -LiteralPath $Path -Value $Json -Encoding UTF8
        }
    }

    Context 'Resolve-DotfilesWindowsFeature' {
        It 'returns only features selected by INSTALL_FEATURES' {
            $configDir = Get-TestConfigDirectory
            try {
                $featuresPath = Join-Path $configDir 'windows-features.json'
                $bootstrapPath = Join-Path $configDir 'dotfiles-bootstrap-variables.json'

                Write-TestJson -Path $featuresPath -Json '{"hyperv":["HypervisorPlatform","Microsoft-Hyper-V-All"],"wsl":["VirtualMachinePlatform"]}'
                Write-TestJson -Path $bootstrapPath -Json '{"INSTALL_FEATURES":["wsl"]}'

                $features = @(Resolve-DotfilesWindowsFeature -ConfigPath $featuresPath -BootstrapPath $bootstrapPath)
                if (($features -join ',') -ne 'VirtualMachinePlatform') {
                    throw "Expected only the WSL feature, got '$($features -join ',')'."
                }
            }
            finally {
                Remove-Item -LiteralPath $configDir -Recurse -Force
            }
        }

        It 'returns no features when INSTALL_FEATURES is explicitly empty' {
            $configDir = Get-TestConfigDirectory
            try {
                $featuresPath = Join-Path $configDir 'windows-features.json'
                $bootstrapPath = Join-Path $configDir 'dotfiles-bootstrap-variables.json'

                Write-TestJson -Path $featuresPath -Json '{"hyperv":["HypervisorPlatform"],"wsl":["VirtualMachinePlatform"]}'
                Write-TestJson -Path $bootstrapPath -Json '{"INSTALL_FEATURES":[]}'

                $features = Resolve-DotfilesWindowsFeature -ConfigPath $featuresPath -BootstrapPath $bootstrapPath
                if ($features.Count -ne 0) {
                    throw "Expected no features, got '$($features -join ',')'."
                }
            }
            finally {
                Remove-Item -LiteralPath $configDir -Recurse -Force
            }
        }

        It 'deduplicates feature names case-insensitively' {
            $configDir = Get-TestConfigDirectory
            try {
                $featuresPath = Join-Path $configDir 'windows-features.json'
                $bootstrapPath = Join-Path $configDir 'dotfiles-bootstrap-variables.json'

                Write-TestJson -Path $featuresPath -Json '{"hyperv":["HypervisorPlatform"],"wsl":["hypervisorplatform"]}'
                Write-TestJson -Path $bootstrapPath -Json '{}'

                $features = @(Resolve-DotfilesWindowsFeature -ConfigPath $featuresPath -BootstrapPath $bootstrapPath)
                if ($features.Count -ne 1 -or $features[0] -ne 'HypervisorPlatform') {
                    throw "Expected one deduplicated feature, got '$($features -join ',')'."
                }
            }
            finally {
                Remove-Item -LiteralPath $configDir -Recurse -Force
            }
        }
    }

    Context 'Get-DotfilesSetupPlan' {
        It 'builds a module plan from selected feature, package, and setting groups' {
            $configDir = Get-TestConfigDirectory
            try {
                $setupModulesPath = Join-Path $configDir 'setup-modules.json'
                Write-TestJson -Path $setupModulesPath -Json @'
{
  "features": [
    { "name": "windows-features", "script": "Configure-WindowsFeatures.ps1", "requiresAdmin": true, "whenSelected": [ "hyperv", "wsl" ] }
  ],
  "packages": [
    { "name": "winget-packages", "script": "Install-WingetPackages.ps1" }
  ],
  "settings": {
    "base": [
      { "script": "Set-EnvironmentVariables.ps1" }
    ],
    "developer": [
      { "script": "Apply-GitConfig.ps1" }
    ]
  }
}
'@
                $bootstrap = '{"INSTALL_FEATURES":["wsl"],"INSTALL_PACKAGES":["base"],"INSTALL_SETTINGS":["developer"]}' | ConvertFrom-Json

                $plan = Get-DotfilesSetupPlan -DotfilesVariables $bootstrap -ConfigDirectory $configDir
                $scripts = @($plan | ForEach-Object { $_.Script })
                $expected = @('Configure-WindowsFeatures.ps1', 'Install-WingetPackages.ps1', 'Apply-GitConfig.ps1')

                if (($scripts -join ',') -ne ($expected -join ',')) {
                    throw "Expected scripts '$($expected -join ',')', got '$($scripts -join ',')'."
                }

                $featureModule = $plan | Where-Object { $_.Script -eq 'Configure-WindowsFeatures.ps1' } | Select-Object -First 1
                if (-not $featureModule.RequiresAdmin) {
                    throw 'Expected Configure-WindowsFeatures.ps1 to require admin.'
                }
            }
            finally {
                Remove-Item -LiteralPath $configDir -Recurse -Force
            }
        }

        It 'runs WSL 2 state enforcement only when the wsl package group is selected' {
            $configDir = Get-TestConfigDirectory
            try {
                $setupModulesPath = Join-Path $configDir 'setup-modules.json'
                Write-TestJson -Path $setupModulesPath -Json @'
{
  "packages": [
    { "name": "winget-packages", "script": "Install-WingetPackages.ps1" },
    { "name": "wsl2-state", "script": "Configure-WSL2.ps1", "whenSelected": [ "wsl" ] }
  ]
}
'@
                $withWsl = '{"INSTALL_PACKAGES":["wsl"]}' | ConvertFrom-Json
                $withoutWsl = '{"INSTALL_PACKAGES":["base"]}' | ConvertFrom-Json
                $allPackages = '{}' | ConvertFrom-Json
                $noPackages = '{"INSTALL_PACKAGES":[]}' | ConvertFrom-Json

                $wslScripts = @(Get-DotfilesSetupPlan -DotfilesVariables $withWsl -ConfigDirectory $configDir | ForEach-Object { $_.Script })
                if (($wslScripts -join ',') -ne 'Install-WingetPackages.ps1,Configure-WSL2.ps1') {
                    throw "Expected Winget followed by WSL 2 configuration, got '$($wslScripts -join ',')'."
                }

                $baseScripts = @(Get-DotfilesSetupPlan -DotfilesVariables $withoutWsl -ConfigDirectory $configDir | ForEach-Object { $_.Script })
                if (($baseScripts -join ',') -ne 'Install-WingetPackages.ps1') {
                    throw "Expected only the generic Winget module without WSL, got '$($baseScripts -join ',')'."
                }

                $allScripts = @(Get-DotfilesSetupPlan -DotfilesVariables $allPackages -ConfigDirectory $configDir | ForEach-Object { $_.Script })
                if (($allScripts -join ',') -ne 'Install-WingetPackages.ps1,Configure-WSL2.ps1') {
                    throw "Expected all package modules when INSTALL_PACKAGES is absent, got '$($allScripts -join ',')'."
                }

                $noScripts = @(Get-DotfilesSetupPlan -DotfilesVariables $noPackages -ConfigDirectory $configDir | ForEach-Object { $_.Script })
                if ($noScripts.Count -ne 0) {
                    throw "Expected no package modules for an empty INSTALL_PACKAGES selection, got '$($noScripts -join ',')'."
                }
            }
            finally {
                Remove-Item -LiteralPath $configDir -Recurse -Force
            }
        }

        It 'skips package and setting modules for explicit empty selections' {
            $configDir = Get-TestConfigDirectory
            try {
                $setupModulesPath = Join-Path $configDir 'setup-modules.json'
                Write-TestJson -Path $setupModulesPath -Json @'
{
  "features": [
    { "name": "windows-features", "script": "Configure-WindowsFeatures.ps1", "requiresAdmin": true, "whenSelected": [ "hyperv", "wsl" ] }
  ],
  "packages": [
    { "name": "winget-packages", "script": "Install-WingetPackages.ps1" }
  ],
  "settings": {
    "base": [
      { "script": "Set-EnvironmentVariables.ps1" }
    ]
  }
}
'@
                $bootstrap = '{"INSTALL_FEATURES":[],"INSTALL_PACKAGES":[],"INSTALL_SETTINGS":[]}' | ConvertFrom-Json

                $plan = Get-DotfilesSetupPlan -DotfilesVariables $bootstrap -ConfigDirectory $configDir
                if ($plan.Count -ne 0) {
                    throw "Expected empty module plan, got '$(@($plan | ForEach-Object { $_.Script }) -join ',')'."
                }
            }
            finally {
                Remove-Item -LiteralPath $configDir -Recurse -Force
            }
        }

        It 'handles missing module groups without creating null plan entries' {
            $configDir = Get-TestConfigDirectory
            try {
                $setupModulesPath = Join-Path $configDir 'setup-modules.json'
                Write-TestJson -Path $setupModulesPath -Json '{}'
                $bootstrap = '{"INSTALL_FEATURES":["wsl"],"INSTALL_PACKAGES":["base"],"INSTALL_SETTINGS":["developer"]}' | ConvertFrom-Json

                $plan = Get-DotfilesSetupPlan -DotfilesVariables $bootstrap -ConfigDirectory $configDir
                if ($plan.Count -ne 0) {
                    throw "Expected empty module plan for missing groups, got '$(@($plan | ForEach-Object { $_.Script }) -join ',')'."
                }
            }
            finally {
                Remove-Item -LiteralPath $configDir -Recurse -Force
            }
        }
    }

    Context 'Setup dependencies' {
        It 'resolves required package groups from selected settings' {
            $setupConfig = @'
{
  "settings": {
    "base": [
      { "script": "Install-WindowsTerminalSettings.ps1", "requiresPackageGroups": ["base"] }
    ],
    "pwsh": [
      { "script": "Install-OmpConfig.ps1", "requiresPackageGroups": ["pwsh"] }
    ]
  }
}
'@ | ConvertFrom-Json

            $required = @(Get-DotfilesRequiredPackageGroup -SetupConfig $setupConfig -SelectedSettings @('base', 'pwsh'))
            if (($required -join ',') -ne 'base,pwsh') {
                throw "Expected package dependencies 'base,pwsh', got '$($required -join ',')'."
            }
        }

        It 'rejects selected settings with missing package groups' {
            $configDir = Get-TestConfigDirectory
            try {
                $setupModulesPath = Join-Path $configDir 'setup-modules.json'
                Write-TestJson -Path $setupModulesPath -Json '{"settings":{"pwsh":[{"script":"Install-OmpConfig.ps1","requiresPackageGroups":["pwsh"]}]}}'
                $bootstrap = '{"INSTALL_PACKAGES":["base"],"INSTALL_SETTINGS":["pwsh"]}' | ConvertFrom-Json
                $threw = $false

                try {
                    Assert-DotfilesSetupDependencies -DotfilesVariables $bootstrap -ConfigDirectory $configDir
                }
                catch {
                    $threw = $_.Exception.Message -match 'missing package group'
                }

                if (-not $threw) {
                    throw 'Expected missing package dependencies to fail validation.'
                }
            }
            finally {
                Remove-Item -LiteralPath $configDir -Recurse -Force
            }
        }
    }

    Context 'Bootstrap branch persistence' {
        It 'writes a branch override to local configuration' {
            $configDir = Get-TestConfigDirectory
            try {
                $bootstrapPath = Join-Path $configDir 'dotfiles-bootstrap-variables.json'
                Write-TestJson -Path $bootstrapPath -Json '{"GITHUB_DOTFILES_BRANCH":"main"}'

                Set-DotfilesBootstrapBranch -ConfigPath $bootstrapPath -Branch 'develop'
                $bootstrap = Get-Content -LiteralPath $bootstrapPath -Raw | ConvertFrom-Json

                if ($bootstrap.GITHUB_DOTFILES_BRANCH -ne 'develop') {
                    throw "Expected persisted branch 'develop', got '$($bootstrap.GITHUB_DOTFILES_BRANCH)'."
                }
            }
            finally {
                Remove-Item -LiteralPath $configDir -Recurse -Force
            }
        }
    }

    Context 'Test-DotfilesObjectProperty' {
        It 'returns false for null input' {
            $hasProperty = Test-DotfilesObjectProperty -InputObject $null -Name 'INSTALL_FEATURES'
            if ($hasProperty) {
                throw 'Expected null input to report property not present.'
            }
        }
    }

    Context 'Setup script orchestration' {
        It 'builds the setup plan from the cloned repository configuration directory' {
            $setupScript = Get-Content -LiteralPath "$PSScriptRoot/../setup-scripts/setup.ps1" -Raw
            if ($setupScript -notmatch [regex]::Escape('$moduleConfigDirectory = Join-Path $dotfilesDirectory "dotfiles-configurations"')) {
                throw 'Expected setup.ps1 to derive module config from the cloned dotfiles directory.'
            }
            if ($setupScript -notmatch [regex]::Escape('Get-DotfilesSetupPlan -DotfilesVariables $DotfilesVariables -ConfigDirectory $moduleConfigDirectory')) {
                throw 'Expected setup.ps1 to pass the cloned config directory into Get-DotfilesSetupPlan.'
            }
            if ($setupScript -notmatch [regex]::Escape('Assert-DotfilesSetupDependencies -DotfilesVariables $DotfilesVariables -ConfigDirectory $moduleConfigDirectory')) {
                throw 'Expected setup.ps1 to validate package dependencies before running modules.'
            }
        }
    }

    Context 'JSON templates' {
        It 'contains valid JSON in all dotfiles configuration templates' {
            $templateFiles = Get-ChildItem -LiteralPath "$PSScriptRoot/../dotfiles-configurations" -Filter '*.json.example'
            foreach ($file in $templateFiles) {
                try {
                    Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json | Out-Null
                }
                catch {
                    throw "Invalid JSON template '$($file.Name)': $($_.Exception.Message)"
                }
            }
        }
    }
}
