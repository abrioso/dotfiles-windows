Describe 'Setup configuration resolution' {
    BeforeAll {
        . "$PSScriptRoot/../setup-scripts/setup-functions.ps1"

        if (-not (Get-Command Get-CimInstance -ErrorAction SilentlyContinue)) {
            function Get-CimInstance { throw 'Test placeholder must be mocked.' }
        }

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

        function Invoke-TestGit {
            param(
                [Parameter(Mandatory)][string]$Repository,
                [Parameter(Mandatory)][string[]]$ArgumentList
            )

            & git -C $Repository @ArgumentList 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "Git failed in test repository: git $($ArgumentList -join ' ')"
            }
        }

        function New-LegacyTestRepository {
            param(
                [switch]$InvalidLegacyJson,
                [switch]$IncompleteLegacySet,
                [switch]$MultipleLegacyVersions,
                [hashtable]$LegacyJson,
                [switch]$InvalidCurrentTemplate
            )

            $repository = Get-TestConfigDirectory
            $configDirectory = Join-Path $repository 'dotfiles-configurations'
            New-Item -ItemType Directory -Path $configDirectory | Out-Null
            Invoke-TestGit -Repository $repository -ArgumentList @('init', '--quiet')
            Invoke-TestGit -Repository $repository -ArgumentList @('config', 'user.name', 'Legacy Test')
            Invoke-TestGit -Repository $repository -ArgumentList @('config', 'user.email', 'legacy@example.invalid')

            $legacyNames = @(
                'dotfiles-bootstrap-variables.json',
                'git-variables.json',
                'env-variables.json',
                'winget-packages.json'
            )
            for ($index = 0; $index -lt $legacyNames.Count; $index++) {
                if ($IncompleteLegacySet -and $index -eq ($legacyNames.Count - 1)) { continue }
                $defaultJson = switch ($legacyNames[$index]) {
                    'dotfiles-bootstrap-variables.json' { '{"GITHUB_ACCOUNT":"legacy","GITHUB_DOTFILES_REPO":"repo","GITHUB_DOTFILES_BRANCH":"main","WORKSPACE_FOLDER":"workspace","INSTALL_FEATURES":[],"INSTALL_PACKAGES":["base"],"INSTALL_SETTINGS":["base"]}' }
                    'git-variables.json' { '{}' }
                    'env-variables.json' { '{}' }
                    'winget-packages.json' { '{"base":["Git.Git"]}' }
                }
                $json = if ($InvalidLegacyJson -and $index -eq 0) {
                    '{invalid'
                } elseif ($LegacyJson -and $LegacyJson.ContainsKey($legacyNames[$index])) {
                    [string]$LegacyJson[$legacyNames[$index]]
                } else {
                    $defaultJson
                }
                [IO.File]::WriteAllBytes(
                    (Join-Path $configDirectory $legacyNames[$index]),
                    [Text.UTF8Encoding]::new($false).GetBytes($json)
                )
            }
            Invoke-TestGit -Repository $repository -ArgumentList @('add', 'dotfiles-configurations')
            Invoke-TestGit -Repository $repository -ArgumentList @('commit', '--quiet', '-m', 'legacy configuration')
            $firstLegacyCommit = (& git -C $repository rev-parse HEAD).Trim()
            $expectedLegacyCommit = $firstLegacyCommit

            if ($MultipleLegacyVersions) {
                [IO.File]::WriteAllBytes(
                    (Join-Path $configDirectory 'git-variables.json'),
                    [Text.UTF8Encoding]::new($false).GetBytes("{`"legacy`":`"different`"}`r`n")
                )
                Invoke-TestGit -Repository $repository -ArgumentList @('add', 'dotfiles-configurations/git-variables.json')
                Invoke-TestGit -Repository $repository -ArgumentList @('commit', '--quiet', '-m', 'different legacy configuration')
                $expectedLegacyCommit = (& git -C $repository rev-parse HEAD).Trim()
            }

            Invoke-TestGit -Repository $repository -ArgumentList @('rm', '--quiet', '-r', 'dotfiles-configurations')
            Invoke-TestGit -Repository $repository -ArgumentList @('commit', '--quiet', '-m', 'remove legacy configuration')

            New-Item -ItemType Directory -Path $configDirectory | Out-Null
            Copy-Item -LiteralPath "$PSScriptRoot/../dotfiles-configurations/dotfiles-bootstrap-variables.json.example" -Destination $configDirectory
            Copy-Item -LiteralPath "$PSScriptRoot/../dotfiles-configurations/git-variables.json.example" -Destination $configDirectory
            Copy-Item -LiteralPath "$PSScriptRoot/../dotfiles-configurations/env-variables.json.example" -Destination $configDirectory
            Copy-Item -LiteralPath "$PSScriptRoot/../dotfiles-configurations/winget-packages.json.example" -Destination $configDirectory
            Copy-Item -LiteralPath "$PSScriptRoot/../dotfiles-configurations/setup-modules.json.example" -Destination $configDirectory
            Copy-Item -LiteralPath "$PSScriptRoot/../dotfiles-configurations/windows-features.json.example" -Destination $configDirectory
            if ($InvalidCurrentTemplate) {
                [IO.File]::WriteAllText((Join-Path $configDirectory 'winget-packages.json.example'), '{invalid-template')
            }
            Invoke-TestGit -Repository $repository -ArgumentList @('add', 'dotfiles-configurations')
            Invoke-TestGit -Repository $repository -ArgumentList @('commit', '--quiet', '-m', 'add current templates')

            return [pscustomobject]@{
                Path = $repository
                ConfigDirectory = $configDirectory
                LegacyCommit = $expectedLegacyCommit
                FirstLegacyCommit = $firstLegacyCommit
                LegacyNames = $legacyNames
            }
        }

        function Get-RepresentativeLegacyJsonFixture {
            return @{
                'dotfiles-bootstrap-variables.json' = '{"GITHUB_ACCOUNT":"abrioso","GITHUB_DOTFILES_REPO":"dotfiles-windows","GITHUB_DOTFILES_BRANCH":"main","WORKSPACE_FOLDER":"workspace","CUSTOM_PROFILE_FOLDER":"Documents","INSTALL_FEATURES":["hyperv"],"INSTALL_PACKAGES":["base","docker","development","productivity","browsers","multimedia"],"INSTALL_SETTINGS":["base","developer","pwsh"]}'
                'git-variables.json' = '{"user.name":"Legacy Test","user.email":"legacy@example.invalid"}'
                'env-variables.json' = '{"KNOWN":"value","UNKNOWN_ENV":{"nested":true}}'
                'winget-packages.json' = '{"Packages":["9MV8F79FGXTR"],"base":["Git.Git"],"poweruser":[],"browsers":["Microsoft.Edge","Google.Chrome"],"productivity":["Microsoft.Office","Microsoft.PowerBI"],"development":["Git.Git","GitHub.cli","Microsoft.PowerShell","microsoft.azd"],"multimedia":[],"wsl":["Microsoft.WindowsSubsystemForLinux","Canonical.Ubuntu"],"docker":["Docker.DockerDesktop"]}'
            }
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

    Context 'Test-DotfilesWindowsFeaturesEnabled' {
        It 'returns true only when every requested feature is enabled' {
            Mock Get-CimInstance {
                @(
                    [pscustomobject]@{ Name = 'VirtualMachinePlatform'; InstallState = 1 }
                    [pscustomobject]@{ Name = 'Microsoft-Hyper-V-All'; InstallState = 1 }
                )
            }

            $enabled = Test-DotfilesWindowsFeaturesEnabled -FeatureName @('VirtualMachinePlatform', 'Microsoft-Hyper-V-All')
            if (-not $enabled) {
                throw 'All requested features in InstallState 1 must satisfy the non-elevated preflight.'
            }
        }
        It 'matches requested feature names case-insensitively' {
            Mock Get-CimInstance {
                @(
                    [pscustomobject]@{ Name = 'VirtualMachinePlatform'; InstallState = 1 }
                    [pscustomobject]@{ Name = 'Microsoft-Hyper-V-All'; InstallState = 1 }
                )
            }

            $enabled = Test-DotfilesWindowsFeaturesEnabled -FeatureName @('virtualmachineplatform', 'microsoft-hyper-v-all')
            if (-not $enabled) {
                throw 'Requested feature names should match Win32_OptionalFeature names without case sensitivity.'
            }
        }
        It 'returns false when any requested feature is not enabled or cannot be identified exactly' {
            Mock Get-CimInstance {
                @(
                    [pscustomobject]@{ Name = 'VirtualMachinePlatform'; InstallState = 1 }
                    [pscustomobject]@{ Name = 'Microsoft-Hyper-V-All'; InstallState = 2 }
                )
            }

            if (Test-DotfilesWindowsFeaturesEnabled -FeatureName @('VirtualMachinePlatform', 'Microsoft-Hyper-V-All')) {
                throw 'A disabled requested feature must keep the elevated module in the setup plan.'
            }
            if (Test-DotfilesWindowsFeaturesEnabled -FeatureName @('VirtualMachinePlatform', 'MissingFeature')) {
                throw 'A missing requested feature must keep the elevated module in the setup plan.'
            }
        }

        It 'returns false when the non-elevated CIM query fails' {
            Mock Get-CimInstance { throw 'CIM unavailable' }

            if (Test-DotfilesWindowsFeaturesEnabled -FeatureName @('VirtualMachinePlatform')) {
                throw 'An inconclusive preflight must fail closed and preserve elevation.'
            }
        }

        It 'skips the Windows feature module before elevation when the requested state is satisfied' {
            $setupPath = Join-Path $PSScriptRoot '../setup-scripts/setup.ps1'
            $setup = Get-Content -LiteralPath $setupPath -Raw
            $preflightIndex = $setup.IndexOf('Test-DotfilesWindowsFeaturesEnabled')
            $elevationIndex = $setup.IndexOf('Start-Process -FilePath $moduleHost')

            if ($preflightIndex -lt 0 -or $elevationIndex -lt 0 -or $preflightIndex -gt $elevationIndex) {
                throw 'Windows feature state must be checked before setup requests elevation.'
            }
            if ($setup -notmatch 'All requested Windows features are already enabled[\s\S]*?continue') {
                throw 'A satisfied preflight must skip the administrative module entirely.'
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

    Context 'Legacy configuration staging' {
        It 'generates validated current-schema candidates from representative production legacy data' {
            $legacyJson = Get-RepresentativeLegacyJsonFixture
            $legacyBootstrap = $legacyJson['dotfiles-bootstrap-variables.json'] | ConvertFrom-Json
            $legacyBootstrap.INSTALL_FEATURES += 'removed-feature'
            $legacyBootstrap.INSTALL_SETTINGS += 'removed-setting'
            $legacyBootstrap.INSTALL_PACKAGES += 'removed-package'
            $legacyJson['dotfiles-bootstrap-variables.json'] = $legacyBootstrap | ConvertTo-Json -Depth 10
            $legacyJson['git-variables.json'] = ($legacyJson['git-variables.json'] | ConvertFrom-Json | Add-Member -NotePropertyName 'user.custom' -NotePropertyValue 'preserved' -PassThru | ConvertTo-Json -Depth 10)
            $legacyJson['env-variables.json'] = '{"KNOWN":"value","UNKNOWN_ENV":{"nested":true}}'
            $legacyWinget = $legacyJson['winget-packages.json'] | ConvertFrom-Json
            $legacyWinget.browsers += 'Unknown.Vendor.App'
            $legacyJson['winget-packages.json'] = $legacyWinget | ConvertTo-Json -Depth 10

            $testRepository = New-LegacyTestRepository -LegacyJson $legacyJson
            $migrationRoot = Get-TestConfigDirectory
            try {
                $result = Invoke-DotfilesLegacyConfigurationStage -RepositoryRoot $testRepository.Path -ConfigDirectory $testRepository.ConfigDirectory -MigrationRoot $migrationRoot
                $manifest = Get-Content -LiteralPath $result.ManifestPath -Raw | ConvertFrom-Json
                if ($manifest.candidates.Count -ne 4) { throw 'Expected four hash-bound candidate entries.' }
                foreach ($entry in $manifest.candidates) {
                    $candidatePath = Join-Path $result.MigrationDirectory $entry.path
                    if (-not (Test-Path -LiteralPath $candidatePath -PathType Leaf)) { throw "Missing candidate '$($entry.path)'." }
                    if ($entry.sha256 -ne (Get-FileHash -LiteralPath $candidatePath -Algorithm SHA256).Hash.ToLowerInvariant()) { throw "Candidate hash mismatch for '$($entry.path)'." }
                }

                $candidateRoot = Join-Path $result.MigrationDirectory 'candidates'
                $bootstrap = Get-Content -LiteralPath (Join-Path $candidateRoot 'dotfiles-bootstrap-variables.json') -Raw | ConvertFrom-Json
                if ($bootstrap.GITHUB_ACCOUNT -ne 'abrioso' -or $bootstrap.WORKSPACE_FOLDER -ne 'workspace') { throw 'Supported legacy bootstrap values were not preserved.' }
                if ($bootstrap.PSObject.Properties.Name -contains 'CUSTOM_PROFILE_FOLDER') { throw 'Removed bootstrap fields must not enter the candidate.' }
                if (($bootstrap.INSTALL_PACKAGES -join ',') -ne 'base,docker,development,productivity,browsers,multimedia,PowerBI,wsl,pwsh') { throw "Unexpected migrated package selection/order: $($bootstrap.INSTALL_PACKAGES -join ',')" }
                if (($bootstrap.INSTALL_SETTINGS -join ',') -ne 'base,developer,pwsh') { throw 'Supported setting selections were not preserved.' }

                $gitCandidate = Get-Content -LiteralPath (Join-Path $candidateRoot 'git-variables.json') -Raw | ConvertFrom-Json
                if ($gitCandidate.'user.custom' -ne 'preserved' -or $gitCandidate.'core.hooksPath' -ne '') { throw 'Git overlay did not preserve unknown keys and new defaults.' }
                $envCandidate = Get-Content -LiteralPath (Join-Path $candidateRoot 'env-variables.json') -Raw | ConvertFrom-Json
                $knownVariable = @($envCandidate.EnvironmentVariables | Where-Object Name -EQ 'KNOWN')
                $unknownVariable = @($envCandidate.EnvironmentVariables | Where-Object Name -EQ 'UNKNOWN_ENV')
                if ($knownVariable.Count -ne 1 -or $knownVariable[0].Value -ne 'value' -or $knownVariable[0].Scope -ne 'User') {
                    throw 'Flat legacy environment values must migrate to user-scoped runtime entries.'
                }
                if ($unknownVariable.Count -ne 1 -or $unknownVariable[0].Value -ne '{"nested":true}' -or $unknownVariable[0].Scope -ne 'User') {
                    throw 'Complex legacy environment values must be preserved as explicit JSON strings for review.'
                }

                $winget = Get-Content -LiteralPath (Join-Path $candidateRoot 'winget-packages.json') -Raw | ConvertFrom-Json
                if (($winget.PSObject.Properties.Name -join ',') -ne 'Packages,base,poweruser,browsers,productivity,development,multimedia,wsl,docker,PowerBI,pwsh') { throw "Legacy and required catalog group order was not preserved: $($winget.PSObject.Properties.Name -join ',')" }
                if ($winget.browsers[1].id -ne 'Google.Chrome.EXE' -or $winget.browsers[1].scope -ne 'user') { throw 'Chrome alias did not receive current metadata.' }
                if ($winget.wsl[0].id -ne 'Microsoft.WSL' -or $winget.wsl[0].installerType -ne 'wix') { throw 'WSL alias did not receive current metadata.' }
                if ($winget.development[3].id -ne 'Microsoft.Azd' -or $winget.development[3].installerType -ne 'wix') { throw 'Case-insensitive package matching did not receive current metadata.' }
                if ($winget.browsers[-1].id -ne 'Unknown.Vendor.App' -or $winget.browsers[-1].PSObject.Properties.Count -ne 1) { throw 'Unknown package IDs must be preserved without invented metadata.' }
                if ($winget.Packages[0].id -ne '9MV8F79FGXTR') { throw 'Legacy Packages entries must be converted to objects.' }
                $warningText = $manifest.migrationWarnings -join "`n"
                foreach ($warningName in @('CUSTOM_PROFILE_FOLDER', 'Packages', 'removed-feature', 'removed-setting', 'removed-package', 'UNKNOWN_ENV')) {
                    if ($warningText -notmatch [regex]::Escape($warningName)) { throw "Migration warning missing '$warningName'." }
                }

                foreach ($name in $testRepository.LegacyNames) {
                    $originalPath = Join-Path $result.MigrationDirectory "dotfiles-configurations/$name"
                    $objectId = (& git -C $testRepository.Path rev-parse "$($testRepository.LegacyCommit):dotfiles-configurations/$name").Trim()
                    if ($LASTEXITCODE -ne 0) { throw "Cannot resolve representative legacy blob '$name'." }
                    $expected = Get-DotfilesGitBlobBytes -RepositoryRoot $testRepository.Path -ObjectId $objectId
                    if (-not [Linq.Enumerable]::SequenceEqual([byte[]]$expected, [byte[]][IO.File]::ReadAllBytes($originalPath))) { throw "Recovered original '$name' changed during candidate generation." }
                    if (Test-Path -LiteralPath (Join-Path $testRepository.ConfigDirectory $name)) { throw "Local configuration '$name' was created." }
                }
            }
            finally {
                Remove-Item -LiteralPath $testRepository.Path, $migrationRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'fails candidate preflight for invalid templates or non-object candidates without local mutation' -ForEach @(
            @{ InvalidTemplate = $true; InvalidEnvironment = $false; Expected = 'template' }
            @{ InvalidTemplate = $false; InvalidEnvironment = $true; Expected = 'environment candidate' }
        ) {
            $legacy = if ($InvalidEnvironment) { @{ 'env-variables.json' = '[]' } } else { $null }
            $testRepository = New-LegacyTestRepository -LegacyJson $legacy -InvalidCurrentTemplate:$InvalidTemplate
            $migrationRoot = Get-TestConfigDirectory
            try {
                $message = $null
                try { Invoke-DotfilesLegacyConfigurationStage -RepositoryRoot $testRepository.Path -ConfigDirectory $testRepository.ConfigDirectory -MigrationRoot $migrationRoot | Out-Null } catch { $message = $_.Exception.Message }
                if ($message -notmatch $Expected) { throw "Expected candidate preflight failure matching '$Expected', got '$message'." }
                if (@(Get-ChildItem -LiteralPath $migrationRoot -Force).Count -ne 0) { throw 'Candidate failure must remove only this attempt''s external artifacts.' }
                foreach ($name in $testRepository.LegacyNames) {
                    if (Test-Path -LiteralPath (Join-Path $testRepository.ConfigDirectory $name)) { throw "Candidate failure created local configuration '$name'." }
                }
            }
            finally {
                Remove-Item -LiteralPath $testRepository.Path, $migrationRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'stages exact bytes and a hash-bound pending manifest from one prior checked-out commit' {
            $testRepository = New-LegacyTestRepository
            $migrationRoot = Get-TestConfigDirectory
            try {
                $result = Invoke-DotfilesLegacyConfigurationStage `
                    -RepositoryRoot $testRepository.Path `
                    -ConfigDirectory $testRepository.ConfigDirectory `
                    -MigrationRoot $migrationRoot

                if (-not $result.Staged -or -not (Test-Path -LiteralPath $result.MigrationDirectory -PathType Container)) {
                    throw 'Expected a legacy configuration migration to be staged.'
                }
                if ($result.SourceCommit -ne $testRepository.LegacyCommit) {
                    throw "Expected source commit '$($testRepository.LegacyCommit)', got '$($result.SourceCommit)'."
                }

                $manifest = Get-Content -LiteralPath $result.ManifestPath -Raw | ConvertFrom-Json
                $canonicalRepository = [IO.Path]::GetFullPath((& git -C $testRepository.Path rev-parse --show-toplevel).Trim())
                $canonicalConfig = [IO.Path]::GetFullPath($testRepository.ConfigDirectory)
                if ($manifest.status -ne 'pending' -or $manifest.repositoryPath -ne $canonicalRepository -or
                    $manifest.configurationPath -ne $canonicalConfig -or
                    $manifest.sourceCommit -ne $testRepository.LegacyCommit -or $manifest.files.Count -ne 4) {
                    throw 'Pending manifest is not bound to the repository, configuration target, source commit, and four legacy paths.'
                }

                foreach ($entry in $manifest.files) {
                    $stagedPath = Join-Path $result.MigrationDirectory $entry.path
                    $expectedPath = "$($testRepository.LegacyCommit):$($entry.path.Replace('\', '/'))"
                    $objectId = (& git -C $testRepository.Path rev-parse $expectedPath).Trim()
                    if ($LASTEXITCODE -ne 0) { throw "Cannot resolve expected blob '$expectedPath'." }
                    $expectedBytes = Get-DotfilesGitBlobBytes -RepositoryRoot $testRepository.Path -ObjectId $objectId
                    $actualBytes = [IO.File]::ReadAllBytes($stagedPath)
                    if (-not [Linq.Enumerable]::SequenceEqual([byte[]]$expectedBytes, [byte[]]$actualBytes)) {
                        throw "Staged bytes differ for '$($entry.path)'."
                    }
                    $actualHash = (Get-FileHash -LiteralPath $stagedPath -Algorithm SHA256).Hash.ToLowerInvariant()
                    if ($entry.sha256 -ne $actualHash) {
                        throw "Manifest hash does not match '$($entry.path)'."
                    }
                }

                if (Test-Path -LiteralPath $testRepository.ConfigDirectory) {
                    $localJson = @(Get-ChildItem -LiteralPath $testRepository.ConfigDirectory -Filter '*.json' -File)
                    if ($localJson.Count -ne 0) { throw 'Staging must not create local configuration JSON.' }
                }
            }
            finally {
                Remove-Item -LiteralPath $testRepository.Path, $migrationRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'does not stage in a fresh clone whose history contains legacy objects' {
            $source = New-LegacyTestRepository
            $cloneParent = Get-TestConfigDirectory
            $migrationRoot = Get-TestConfigDirectory
            $clone = Join-Path $cloneParent 'fresh-clone'
            try {
                & git clone --quiet $source.Path $clone
                if ($LASTEXITCODE -ne 0) { throw 'Failed to create fresh clone test fixture.' }
                $result = Invoke-DotfilesLegacyConfigurationStage `
                    -RepositoryRoot $clone `
                    -ConfigDirectory (Join-Path $clone 'dotfiles-configurations') `
                    -MigrationRoot $migrationRoot
                if ($result.Staged) { throw 'A fresh clone must not stage from history/object existence alone.' }
                if (@(Get-ChildItem -LiteralPath $migrationRoot -Force).Count -ne 0) {
                    throw 'Fresh clone detection must not create migration artifacts.'
                }
            }
            finally {
                Remove-Item -LiteralPath $source.Path, $cloneParent, $migrationRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'selects the most recent qualifying legacy checkout in a long-lived reflog' {
            $testRepository = New-LegacyTestRepository -MultipleLegacyVersions
            $migrationRoot = Get-TestConfigDirectory
            try {
                $result = Invoke-DotfilesLegacyConfigurationStage `
                    -RepositoryRoot $testRepository.Path `
                    -ConfigDirectory $testRepository.ConfigDirectory `
                    -MigrationRoot $migrationRoot

                if (-not $result.Staged -or $result.SourceCommit -ne $testRepository.LegacyCommit) {
                    throw "Expected latest legacy commit '$($testRepository.LegacyCommit)', got '$($result.SourceCommit)'."
                }
                if ($result.SourceCommit -eq $testRepository.FirstLegacyCommit) {
                    throw 'An older qualifying reflog entry must not override the nearest legacy checkout.'
                }
            }
            finally {
                Remove-Item -LiteralPath $testRepository.Path, $migrationRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'fails closed for incomplete or invalid legacy blobs' -ForEach @(
            @{ Fixture = @{ IncompleteLegacySet = $true }; Expected = 'incomplete' }
            @{ Fixture = @{ InvalidLegacyJson = $true }; Expected = 'valid JSON' }
        ) {
            $testRepository = New-LegacyTestRepository @Fixture
            $migrationRoot = Get-TestConfigDirectory
            try {
                $message = $null
                try {
                    Invoke-DotfilesLegacyConfigurationStage `
                        -RepositoryRoot $testRepository.Path `
                        -ConfigDirectory $testRepository.ConfigDirectory `
                        -MigrationRoot $migrationRoot | Out-Null
                }
                catch { $message = $_.Exception.Message }
                if ($message -notmatch $Expected) {
                    throw "Expected failure matching '$Expected', got '$message'."
                }
                if (@(Get-ChildItem -LiteralPath $migrationRoot -Force).Count -ne 0) {
                    throw 'Failed staging must clean only its newly-created artifacts.'
                }
                if (Test-Path -LiteralPath $testRepository.ConfigDirectory) {
                    if (@(Get-ChildItem -LiteralPath $testRepository.ConfigDirectory -Filter '*.json' -File).Count -ne 0) {
                        throw 'Legacy validation failure must not create local configuration JSON.'
                    }
                }
            }
            finally {
                Remove-Item -LiteralPath $testRepository.Path, $migrationRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'rejects configuration and migration paths outside their approved boundaries' -ForEach @(
            @{ ExternalConfig = $true; InRepositoryMigration = $false; Expected = 'repository''s dotfiles-configurations' }
            @{ ExternalConfig = $false; InRepositoryMigration = $true; Expected = 'outside the dotfiles repository' }
        ) {
            $testRepository = New-LegacyTestRepository
            $externalConfigDirectory = Get-TestConfigDirectory
            $externalMigration = Get-TestConfigDirectory
            try {
                $configDirectory = if ($ExternalConfig) { $externalConfigDirectory } else { $testRepository.ConfigDirectory }
                $migrationRoot = if ($InRepositoryMigration) {
                    Join-Path $testRepository.Path 'migration-output'
                } else {
                    $externalMigration
                }
                $message = $null
                try {
                    Invoke-DotfilesLegacyConfigurationStage `
                        -RepositoryRoot $testRepository.Path `
                        -ConfigDirectory $configDirectory `
                        -MigrationRoot $migrationRoot | Out-Null
                }
                catch { $message = $_.Exception.Message }
                if ($message -notmatch $Expected) {
                    throw "Expected path-boundary failure matching '$Expected', got '$message'."
                }
                if (Test-Path -LiteralPath $migrationRoot) {
                    if (@(Get-ChildItem -LiteralPath $migrationRoot -Force).Count -ne 0) {
                        throw 'Rejected path boundaries must not create migration artifacts.'
                    }
                }
            }
            finally {
                Remove-Item -LiteralPath $testRepository.Path, $externalConfigDirectory, $externalMigration -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'preserves a complete valid customized current configuration instead of staging older reflog data' {
            $testRepository = New-LegacyTestRepository
            $migrationRoot = Get-TestConfigDirectory
            try {
                foreach ($name in $testRepository.LegacyNames) {
                    Copy-Item -LiteralPath (Join-Path $testRepository.ConfigDirectory "$name.example") -Destination (Join-Path $testRepository.ConfigDirectory $name)
                }
                $gitPath = Join-Path $testRepository.ConfigDirectory 'git-variables.json'
                $currentGit = Get-Content -LiteralPath $gitPath -Raw | ConvertFrom-Json
                $currentGit.'user.name' = 'Current User'
                $currentGit | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $gitPath -Encoding UTF8
                $before = @{}
                foreach ($name in $testRepository.LegacyNames) {
                    $before[$name] = [IO.File]::ReadAllBytes((Join-Path $testRepository.ConfigDirectory $name))
                }

                $result = Invoke-DotfilesLegacyConfigurationStage `
                    -RepositoryRoot $testRepository.Path `
                    -ConfigDirectory $testRepository.ConfigDirectory `
                    -MigrationRoot $migrationRoot

                if ($result.Staged) { throw 'Customized current configuration must not be replaced by older reflog recovery.' }
                foreach ($name in $testRepository.LegacyNames) {
                    if (-not [Linq.Enumerable]::SequenceEqual([byte[]]$before[$name], [IO.File]::ReadAllBytes((Join-Path $testRepository.ConfigDirectory $name)))) {
                        throw "Current configuration '$name' changed while recovery was skipped."
                    }
                }
                if (@(Get-ChildItem -LiteralPath $migrationRoot -Force).Count -ne 0) {
                    throw 'Skipping recovery for current configuration must not create migration artifacts.'
                }
            }
            finally {
                Remove-Item -LiteralPath $testRepository.Path, $migrationRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'fails closed for partial or invalid current configuration without changing it' -ForEach @(
            @{ InvalidCurrent = $false; Expected = 'partial' }
            @{ InvalidCurrent = $true; Expected = 'valid JSON' }
        ) {
            $testRepository = New-LegacyTestRepository
            $migrationRoot = Get-TestConfigDirectory
            try {
                New-Item -ItemType Directory -Path $testRepository.ConfigDirectory -Force | Out-Null
                $names = if ($InvalidCurrent) { $testRepository.LegacyNames } else { @($testRepository.LegacyNames[0]) }
                foreach ($name in $names) {
                    $content = if ($InvalidCurrent -and $name -eq $testRepository.LegacyNames[0]) { '{invalid-current' } else { '{"current":true}' }
                    [IO.File]::WriteAllText((Join-Path $testRepository.ConfigDirectory $name), $content)
                }
                $before = @{}
                foreach ($name in $names) { $before[$name] = [IO.File]::ReadAllBytes((Join-Path $testRepository.ConfigDirectory $name)) }

                $message = $null
                try {
                    Invoke-DotfilesLegacyConfigurationStage `
                        -RepositoryRoot $testRepository.Path `
                        -ConfigDirectory $testRepository.ConfigDirectory `
                        -MigrationRoot $migrationRoot | Out-Null
                }
                catch { $message = $_.Exception.Message }
                if ($message -notmatch $Expected) { throw "Expected failure matching '$Expected', got '$message'." }
                foreach ($name in $names) {
                    $after = [IO.File]::ReadAllBytes((Join-Path $testRepository.ConfigDirectory $name))
                    if (-not [Linq.Enumerable]::SequenceEqual([byte[]]$before[$name], $after)) {
                        throw "Current configuration '$name' was changed during failed staging."
                    }
                }
                if (@(Get-ChildItem -LiteralPath $migrationRoot -Force).Count -ne 0) {
                    throw 'Current configuration failure must not create migration artifacts.'
                }
            }
            finally {
                Remove-Item -LiteralPath $testRepository.Path, $migrationRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'rejects a conflicting pending manifest without overwriting the completed stage' {
            $testRepository = New-LegacyTestRepository
            $migrationRoot = Get-TestConfigDirectory
            try {
                $first = Invoke-DotfilesLegacyConfigurationStage `
                    -RepositoryRoot $testRepository.Path `
                    -ConfigDirectory $testRepository.ConfigDirectory `
                    -MigrationRoot $migrationRoot
                $manifestBytes = [IO.File]::ReadAllBytes($first.ManifestPath)
                $message = $null
                try {
                    Invoke-DotfilesLegacyConfigurationStage `
                        -RepositoryRoot $testRepository.Path `
                        -ConfigDirectory $testRepository.ConfigDirectory `
                        -MigrationRoot $migrationRoot | Out-Null
                }
                catch { $message = $_.Exception.Message }
                if ($message -notmatch 'pending manifest') { throw "Expected pending manifest conflict, got '$message'." }
                if (-not [Linq.Enumerable]::SequenceEqual($manifestBytes, [IO.File]::ReadAllBytes($first.ManifestPath))) {
                    throw 'A conflicting pending manifest must never be overwritten.'
                }
                $migrationDirectories = @(Get-ChildItem -LiteralPath (Split-Path -Parent $first.MigrationDirectory) -Directory)
                if ($migrationDirectories.Count -ne 1) { throw 'Conflict handling must not leave a second staging directory.' }
            }
            finally {
                Remove-Item -LiteralPath $testRepository.Path, $migrationRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'stops configure after staging in interactive and non-interactive modes' -ForEach @(
            @{ NonInteractive = $false }
            @{ NonInteractive = $true }
        ) {
            $testRepository = New-LegacyTestRepository
            $localAppData = Get-TestConfigDirectory
            $oldLocalAppData = $env:LOCALAPPDATA
            try {
                $env:LOCALAPPDATA = $localAppData
                $arguments = @{
                    ConfigDirectory = $testRepository.ConfigDirectory
                    RepositoryRoot = $testRepository.Path
                    NonInteractive = $NonInteractive
                }
                $output = (& "$PSScriptRoot/../setup-scripts/configure.ps1" @arguments 6>&1) | Out-String
                $migrationRoot = Join-Path (Join-Path $localAppData 'dotfiles') 'migrations'
                $manifests = if (Test-Path -LiteralPath $migrationRoot) { @(Get-ChildItem -LiteralPath $migrationRoot -Filter 'pending.json' -File -Recurse) } else { @() }
                if ($output -notmatch 'Migration directory:' -or $manifests.Count -ne 1) {
                    throw 'Configure must report the external migration directory and stop.'
                }
                if (Test-Path -LiteralPath $testRepository.ConfigDirectory) {
                    if (@(Get-ChildItem -LiteralPath $testRepository.ConfigDirectory -Filter '*.json' -File).Count -ne 0) {
                        throw 'Configure must not generate defaults when legacy staging occurs.'
                    }
                }
            }
            finally {
                $env:LOCALAPPDATA = $oldLocalAppData
                Remove-Item -LiteralPath $testRepository.Path, $localAppData -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'Legacy configuration transactional apply' {
        BeforeAll {
            function New-LegacyApplyFixture {
                $repository = New-LegacyTestRepository
                $migrationRoot = Get-TestConfigDirectory
                $stage = Invoke-DotfilesLegacyConfigurationStage `
                    -RepositoryRoot $repository.Path `
                    -ConfigDirectory $repository.ConfigDirectory `
                    -MigrationRoot $migrationRoot
                return [pscustomobject]@{
                    Repository = $repository
                    MigrationRoot = $migrationRoot
                    Stage = $stage
                }
            }

            function Get-LegacyApplyBytes {
                param([Parameter(Mandatory)]$Fixture)
                $result = @{}
                foreach ($name in $Fixture.Repository.LegacyNames) {
                    $path = Join-Path $Fixture.Repository.ConfigDirectory $name
                    $result[$name] = if (Test-Path -LiteralPath $path) { [IO.File]::ReadAllBytes($path) } else { $null }
                }
                return $result
            }
        }

        It 'declines an interactive pending migration by default without changing any bytes' {
            $fixture = New-LegacyApplyFixture
            try {
                $manifestBefore = [IO.File]::ReadAllBytes($fixture.Stage.ManifestPath)
                $candidateBefore = @{}
                $manifest = Get-Content -LiteralPath $fixture.Stage.ManifestPath -Raw | ConvertFrom-Json
                foreach ($entry in $manifest.candidates) {
                    $path = Join-Path $fixture.Stage.MigrationDirectory $entry.path
                    $candidateBefore[$entry.path] = [IO.File]::ReadAllBytes($path)
                }

                $pending = Get-DotfilesLegacyMigrationState -RepositoryRoot $fixture.Repository.Path -ConfigDirectory $fixture.Repository.ConfigDirectory -MigrationRoot $fixture.MigrationRoot
                $result = Invoke-DotfilesLegacyMigrationPrompt -MigrationState $pending -ReadConfirmation { '' }

                if ($result.Applied -or -not $result.Declined) { throw 'An empty confirmation must decline the migration.' }
                if (-not [Linq.Enumerable]::SequenceEqual($manifestBefore, [IO.File]::ReadAllBytes($fixture.Stage.ManifestPath))) { throw 'Decline changed the manifest.' }
                foreach ($entry in $manifest.candidates) {
                    $path = Join-Path $fixture.Stage.MigrationDirectory $entry.path
                    if (-not [Linq.Enumerable]::SequenceEqual([byte[]]$candidateBefore[$entry.path], [IO.File]::ReadAllBytes($path))) { throw "Decline changed candidate '$($entry.path)'." }
                }
                if (@(Get-ChildItem -LiteralPath $fixture.Repository.ConfigDirectory -Filter '*.json' -File).Count -ne 0) { throw 'Decline generated current configuration.' }
            }
            finally { Remove-Item -LiteralPath $fixture.Repository.Path, $fixture.MigrationRoot -Recurse -Force -ErrorAction SilentlyContinue }
        }

        It 'reports an existing pending migration noninteractively without applying or restaging it' {
            $fixture = $null
            $oldLocalAppData = $env:LOCALAPPDATA
            $localAppData = Get-TestConfigDirectory
            try {
                $env:LOCALAPPDATA = $localAppData
                $repository = New-LegacyTestRepository
                $stage = Invoke-DotfilesLegacyConfigurationStage -RepositoryRoot $repository.Path -ConfigDirectory $repository.ConfigDirectory
                $fixture = [pscustomobject]@{
                    Repository = $repository
                    MigrationRoot = Join-Path $localAppData 'dotfiles/migrations'
                    Stage = $stage
                }
                $manifestBefore = [IO.File]::ReadAllBytes($fixture.Stage.ManifestPath)

                $output = (& "$PSScriptRoot/../setup-scripts/configure.ps1" -NonInteractive -RepositoryRoot $fixture.Repository.Path -ConfigDirectory $fixture.Repository.ConfigDirectory 6>&1) | Out-String
                if ($output -notmatch 'pending' -or $output -notmatch [regex]::Escape($fixture.Stage.ManifestPath) -or $output -notmatch 'candidates') { throw "Pending report was incomplete: $output" }
                if (-not [Linq.Enumerable]::SequenceEqual($manifestBefore, [IO.File]::ReadAllBytes($fixture.Stage.ManifestPath))) { throw 'Noninteractive configure changed the manifest.' }
                if (@(Get-ChildItem -LiteralPath $fixture.Repository.ConfigDirectory -Filter '*.json' -File).Count -ne 0) { throw 'Noninteractive pending handling generated configuration.' }
                if (@(Get-ChildItem -LiteralPath (Split-Path -Parent $fixture.Stage.ManifestPath) -Directory).Count -ne 1) { throw 'Pending handling restaged the migration.' }
            }
            finally {
                $env:LOCALAPPDATA = $oldLocalAppData
                if ($fixture) { Remove-Item -LiteralPath $fixture.Repository.Path -Recurse -Force -ErrorAction SilentlyContinue }
                Remove-Item -LiteralPath $localAppData -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'applies all four candidates transactionally and marks the manifest applied' {
            $fixture = New-LegacyApplyFixture
            try {
                $pending = Get-DotfilesLegacyMigrationState -RepositoryRoot $fixture.Repository.Path -ConfigDirectory $fixture.Repository.ConfigDirectory -MigrationRoot $fixture.MigrationRoot
                $result = Invoke-DotfilesLegacyMigrationPrompt -MigrationState $pending -ReadConfirmation { 'yes' }
                if (-not $result.Applied -or $result.Results.Count -ne 4) { throw 'Expected four successful apply results.' }
                $manifest = Get-Content -LiteralPath $fixture.Stage.ManifestPath -Raw | ConvertFrom-Json
                if ($manifest.status -ne 'applied' -or -not (Test-Path -LiteralPath $manifest.backupDirectory -PathType Container) -or $manifest.backups.Count -ne 4 -or $manifest.installed.Count -ne 4) { throw 'Applied manifest is missing transactional metadata.' }
                foreach ($entry in $manifest.installed) {
                    $target = Join-Path $fixture.Repository.ConfigDirectory $entry.path
                    if ($entry.sha256 -ne (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()) { throw "Installed hash mismatch for '$($entry.path)'." }
                }
            }
            finally { Remove-Item -LiteralPath $fixture.Repository.Path, $fixture.MigrationRoot -Recurse -Force -ErrorAction SilentlyContinue }
        }

        It 'rejects tampered, stale, and user-owned states without target mutation' -ForEach @(
            @{ Kind = 'candidate'; Expected = 'hash' }
            @{ Kind = 'source'; Expected = 'hash' }
            @{ Kind = 'manifest'; Expected = 'repository' }
            @{ Kind = 'duplicate'; Expected = 'exactly four' }
            @{ Kind = 'current'; Expected = 'user-owned' }
        ) {
            $fixture = New-LegacyApplyFixture
            try {
                $manifest = Get-Content -LiteralPath $fixture.Stage.ManifestPath -Raw | ConvertFrom-Json
                switch ($Kind) {
                    'candidate' { [IO.File]::AppendAllText((Join-Path $fixture.Stage.MigrationDirectory $manifest.candidates[0].path), ' ') }
                    'source' { [IO.File]::AppendAllText((Join-Path $fixture.Stage.MigrationDirectory $manifest.files[0].path), ' ') }
                    'manifest' { $manifest.repositoryPath = $fixture.MigrationRoot; $manifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $fixture.Stage.ManifestPath -Encoding UTF8 }
                    'duplicate' { $manifest.candidates = @($manifest.candidates[0], $manifest.candidates[0], $manifest.candidates[1], $manifest.candidates[2]); $manifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $fixture.Stage.ManifestPath -Encoding UTF8 }
                    'current' {
                        foreach ($name in $fixture.Repository.LegacyNames) { Copy-Item -LiteralPath (Join-Path $fixture.Repository.ConfigDirectory "$name.example") -Destination (Join-Path $fixture.Repository.ConfigDirectory $name) }
                        $gitPath = Join-Path $fixture.Repository.ConfigDirectory 'git-variables.json'
                        $git = Get-Content -LiteralPath $gitPath -Raw | ConvertFrom-Json
                        $git.'user.name' = 'User Owned'
                        $git | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $gitPath -Encoding UTF8
                    }
                }
                $before = Get-LegacyApplyBytes -Fixture $fixture
                $message = $null
                try {
                    $pending = Get-DotfilesLegacyMigrationState -RepositoryRoot $fixture.Repository.Path -ConfigDirectory $fixture.Repository.ConfigDirectory -MigrationRoot $fixture.MigrationRoot
                    Invoke-DotfilesLegacyMigrationApply -MigrationState $pending | Out-Null
                } catch { $message = $_.Exception.Message }
                if ($message -notmatch $Expected) { throw "Expected rejection matching '$Expected', got '$message'." }
                $after = Get-LegacyApplyBytes -Fixture $fixture
                foreach ($name in $fixture.Repository.LegacyNames) {
                    if ($null -eq $before[$name]) {
                        if ($null -ne $after[$name]) { throw "Rejected apply created '$name'." }
                    } elseif (-not [Linq.Enumerable]::SequenceEqual([byte[]]$before[$name], [byte[]]$after[$name])) { throw "Rejected apply changed '$name'." }
                }
            }
            finally { Remove-Item -LiteralPath $fixture.Repository.Path, $fixture.MigrationRoot -Recurse -Force -ErrorAction SilentlyContinue }
        }

        It 'rolls back completed replacements in reverse after a later install failure' {
            $fixture = New-LegacyApplyFixture
            try {
                foreach ($name in $fixture.Repository.LegacyNames) { Copy-Item -LiteralPath (Join-Path $fixture.Repository.ConfigDirectory "$name.example") -Destination (Join-Path $fixture.Repository.ConfigDirectory $name) }
                $before = Get-LegacyApplyBytes -Fixture $fixture
                $pending = Get-DotfilesLegacyMigrationState -RepositoryRoot $fixture.Repository.Path -ConfigDirectory $fixture.Repository.ConfigDirectory -MigrationRoot $fixture.MigrationRoot
                $message = $null
                try {
                    Invoke-DotfilesLegacyMigrationApply -MigrationState $pending -BeforeInstall { param($index) if ($index -eq 2) { throw 'forced later install failure' } } | Out-Null
                } catch { $message = $_.Exception.Message }
                if ($message -notmatch 'forced later install failure' -or $message -notmatch 'rolled back') { throw "Expected primary and rollback report, got '$message'." }
                $after = Get-LegacyApplyBytes -Fixture $fixture
                foreach ($name in $fixture.Repository.LegacyNames) {
                    if (-not [Linq.Enumerable]::SequenceEqual([byte[]]$before[$name], [byte[]]$after[$name])) { throw "Rollback did not restore '$name'." }
                }
                if ((Get-Content -LiteralPath $fixture.Stage.ManifestPath -Raw | ConvertFrom-Json).status -ne 'pending') { throw 'Failed apply changed manifest status.' }
            }
            finally { Remove-Item -LiteralPath $fixture.Repository.Path, $fixture.MigrationRoot -Recurse -Force -ErrorAction SilentlyContinue }
        }

        It 'rolls back configuration when applied-manifest publication fails' {
            $fixture = New-LegacyApplyFixture
            try {
                foreach ($name in $fixture.Repository.LegacyNames) { Copy-Item -LiteralPath (Join-Path $fixture.Repository.ConfigDirectory "$name.example") -Destination (Join-Path $fixture.Repository.ConfigDirectory $name) }
                $before = Get-LegacyApplyBytes -Fixture $fixture
                $pending = Get-DotfilesLegacyMigrationState -RepositoryRoot $fixture.Repository.Path -ConfigDirectory $fixture.Repository.ConfigDirectory -MigrationRoot $fixture.MigrationRoot
                $message = $null
                try {
                    Invoke-DotfilesLegacyMigrationApply -MigrationState $pending -BeforeManifestPublish { throw 'forced manifest publication failure' } | Out-Null
                } catch { $message = $_.Exception.Message }
                if ($message -notmatch 'forced manifest publication failure' -or $message -notmatch 'rolled back') { throw "Expected publication failure and rollback report, got '$message'." }
                $after = Get-LegacyApplyBytes -Fixture $fixture
                foreach ($name in $fixture.Repository.LegacyNames) {
                    if (-not [Linq.Enumerable]::SequenceEqual([byte[]]$before[$name], [byte[]]$after[$name])) { throw "Manifest publication rollback did not restore '$name'." }
                }
                if ((Get-Content -LiteralPath $fixture.Stage.ManifestPath -Raw | ConvertFrom-Json).status -ne 'pending') { throw 'Publication failure changed manifest status.' }
            }
            finally { Remove-Item -LiteralPath $fixture.Repository.Path, $fixture.MigrationRoot -Recurse -Force -ErrorAction SilentlyContinue }
        }

        It 'rejects malformed or stale applied manifests before returning an applied state' -ForEach @(
            @{ Kind = 'repository'; Expected = 'repository'; ExistingBackups = $false }
            @{ Kind = 'statusCase'; Expected = 'status'; ExistingBackups = $false }
            @{ Kind = 'configuration'; Expected = 'configuration'; ExistingBackups = $false }
            @{ Kind = 'sourceCommit'; Expected = 'source commit'; ExistingBackups = $false }
            @{ Kind = 'sourceCommitMissing'; Expected = 'source commit'; ExistingBackups = $false }
            @{ Kind = 'migrationWarningsNull'; Expected = 'migration warnings'; ExistingBackups = $false }
            @{ Kind = 'migrationWarningsString'; Expected = 'migration warnings'; ExistingBackups = $false }
            @{ Kind = 'migrationWarningsObject'; Expected = 'migration warnings'; ExistingBackups = $false }
            @{ Kind = 'migrationWarningsBool'; Expected = 'migration warnings'; ExistingBackups = $false }
            @{ Kind = 'installedSha'; Expected = 'installed'; ExistingBackups = $false }
            @{ Kind = 'installedDuplicate'; Expected = 'installed'; ExistingBackups = $false }
            @{ Kind = 'installedReordered'; Expected = 'installed'; ExistingBackups = $false }
            @{ Kind = 'targetMissing'; Expected = 'installed target'; ExistingBackups = $false }
            @{ Kind = 'targetTampered'; Expected = 'installed target hash'; ExistingBackups = $false }
            @{ Kind = 'candidateTampered'; Expected = 'candidate.*hash'; ExistingBackups = $false }
            @{ Kind = 'originalTampered'; Expected = 'original.*hash'; ExistingBackups = $false }
            @{ Kind = 'backupMalformed'; Expected = 'backup'; ExistingBackups = $false }
            @{ Kind = 'backupTampered'; Expected = 'backup.*hash'; ExistingBackups = $true }
        ) {
            $fixture = New-LegacyApplyFixture
            try {
                if ($ExistingBackups) {
                    foreach ($name in $fixture.Repository.LegacyNames) {
                        Copy-Item -LiteralPath (Join-Path $fixture.Repository.ConfigDirectory "$name.example") -Destination (Join-Path $fixture.Repository.ConfigDirectory $name)
                    }
                }
                $pending = Get-DotfilesLegacyMigrationState -RepositoryRoot $fixture.Repository.Path -ConfigDirectory $fixture.Repository.ConfigDirectory -MigrationRoot $fixture.MigrationRoot
                Invoke-DotfilesLegacyMigrationApply -MigrationState $pending | Out-Null
                $manifest = Get-Content -LiteralPath $fixture.Stage.ManifestPath -Raw | ConvertFrom-Json
                switch ($Kind) {
                    'repository' { $manifest.repositoryPath = $fixture.MigrationRoot }
                    'statusCase' { $manifest.status = 'Applied' }
                    'configuration' { $manifest.configurationPath = $fixture.MigrationRoot }
                    'sourceCommit' { $manifest.sourceCommit = '../not-a-commit' }
                    'sourceCommitMissing' { $manifest.sourceCommit = '0000000000000000000000000000000000000000' }
                    'migrationWarningsNull' { $manifest.migrationWarnings = $null }
                    'migrationWarningsString' { $manifest.migrationWarnings = 'warning' }
                    'migrationWarningsObject' { $manifest.migrationWarnings = [pscustomobject]@{ warning = 'value' } }
                    'migrationWarningsBool' { $manifest.migrationWarnings = $false }
                    'installedSha' { $manifest.installed[0].sha256 = 'not-a-sha' }
                    'installedDuplicate' { $manifest.installed = @($manifest.installed[0], $manifest.installed[0], $manifest.installed[2], $manifest.installed[3]) }
                    'installedReordered' { $manifest.installed = @($manifest.installed[1], $manifest.installed[0], $manifest.installed[2], $manifest.installed[3]) }
                    'targetMissing' { Remove-Item -LiteralPath (Join-Path $fixture.Repository.ConfigDirectory $manifest.installed[0].path) -Force }
                    'targetTampered' { [IO.File]::AppendAllText((Join-Path $fixture.Repository.ConfigDirectory $manifest.installed[0].path), ' ') }
                    'candidateTampered' { [IO.File]::AppendAllText((Join-Path $fixture.Stage.MigrationDirectory $manifest.candidates[0].path), ' ') }
                    'originalTampered' { [IO.File]::AppendAllText((Join-Path $fixture.Stage.MigrationDirectory $manifest.files[0].path), ' ') }
                    'backupMalformed' { $manifest.backups[0].existed = 'false' }
                    'backupTampered' { [IO.File]::AppendAllText([string]$manifest.backups[0].backupPath, ' ') }
                }
                if ($Kind -in @('repository', 'statusCase', 'configuration', 'sourceCommit', 'sourceCommitMissing', 'migrationWarningsNull', 'migrationWarningsString', 'migrationWarningsObject', 'migrationWarningsBool', 'installedSha', 'installedDuplicate', 'installedReordered', 'backupMalformed')) {
                    $manifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $fixture.Stage.ManifestPath -Encoding UTF8
                }

                $message = $null
                try {
                    Get-DotfilesLegacyMigrationState -RepositoryRoot $fixture.Repository.Path -ConfigDirectory $fixture.Repository.ConfigDirectory -MigrationRoot $fixture.MigrationRoot | Out-Null
                }
                catch { $message = $_.Exception.Message }
                if ($message -notmatch $Expected) { throw "Expected applied-state rejection matching '$Expected', got '$message'." }
            }
            finally { Remove-Item -LiteralPath $fixture.Repository.Path, $fixture.MigrationRoot -Recurse -Force -ErrorAction SilentlyContinue }
        }

        It 'treats an applied manifest as an idempotent rerun state without reapplying' {
            $fixture = New-LegacyApplyFixture
            try {
                $pending = Get-DotfilesLegacyMigrationState -RepositoryRoot $fixture.Repository.Path -ConfigDirectory $fixture.Repository.ConfigDirectory -MigrationRoot $fixture.MigrationRoot
                Invoke-DotfilesLegacyMigrationApply -MigrationState $pending | Out-Null
                $before = Get-LegacyApplyBytes -Fixture $fixture
                $applied = Get-DotfilesLegacyMigrationState -RepositoryRoot $fixture.Repository.Path -ConfigDirectory $fixture.Repository.ConfigDirectory -MigrationRoot $fixture.MigrationRoot
                if ($applied.Status -ne 'applied') { throw 'Expected applied discovery state.' }
                $result = Invoke-DotfilesLegacyMigrationPrompt -MigrationState $applied -ReadConfirmation { throw 'Applied rerun must not prompt.' }
                if ($result.Applied -or -not $result.AlreadyApplied) { throw 'Applied rerun must be a no-op.' }
                $after = Get-LegacyApplyBytes -Fixture $fixture
                foreach ($name in $fixture.Repository.LegacyNames) {
                    if (-not [Linq.Enumerable]::SequenceEqual([byte[]]$before[$name], [byte[]]$after[$name])) { throw "Applied rerun changed '$name'." }
                }
            }
            finally { Remove-Item -LiteralPath $fixture.Repository.Path, $fixture.MigrationRoot -Recurse -Force -ErrorAction SilentlyContinue }
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
