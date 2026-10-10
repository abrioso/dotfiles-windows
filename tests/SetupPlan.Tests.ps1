Describe 'Read-only setup plan' {
    BeforeAll {
        $repositoryRoot = Split-Path -Parent $PSScriptRoot
        . "$repositoryRoot/setup-scripts/setup-functions.ps1"
        . "$repositoryRoot/setup-scripts/setup-plan.ps1"
        $hosts = @((Get-Command pwsh).Source, "$env:SystemRoot/System32/WindowsPowerShell/v1.0/powershell.exe")
        function Save-PlanBootstrap {
            $bootstrap | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $bootstrapPath -Encoding UTF8
        }
        function Get-PlanFixtureSnapshot {
            @(Get-ChildItem -LiteralPath $fixtureRoot -Recurse -File | Sort-Object FullName | ForEach-Object {
                "$($_.FullName):$((Get-FileHash -LiteralPath $_.FullName).Hash)"
            }) -join "`n"
        }
    }
    BeforeEach {
        $fixtureRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $configDirectory = Join-Path $fixtureRoot 'dotfiles-configurations'
        New-Item -ItemType Directory -Path $configDirectory | Out-Null
        Copy-Item -LiteralPath "$repositoryRoot/setup-scripts" -Destination $fixtureRoot -Recurse
        Copy-Item -LiteralPath "$repositoryRoot/setup-modules" -Destination $fixtureRoot -Recurse
        foreach ($file in Get-ChildItem "$repositoryRoot/dotfiles-configurations/*.json.example") {
            Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $configDirectory ($file.Name -replace '\.example$', ''))
        }
        $bootstrapPath = Join-Path $configDirectory 'dotfiles-bootstrap-variables.json'
        $bootstrap = Read-DotfilesConfigurationObject $bootstrapPath
        # Trap the mutating orchestration paths if a future change lets planning reach them.
        @'

function Start-Logging { throw 'FORBIDDEN: logging' }
function Initialize-DotfilesConfiguration { throw 'FORBIDDEN: initialization' }
function Install-DotfilesPrerequisites { throw 'FORBIDDEN: prerequisites' }
function Sync-DotfilesLocalConfiguration { throw 'FORBIDDEN: configuration synchronization' }
function Set-DotfilesBootstrapBranch { throw 'FORBIDDEN: saving branch' }
function Start-Process { throw 'FORBIDDEN: child process or elevation' }
function New-Item { throw 'FORBIDDEN: filesystem creation' }
function git { throw 'FORBIDDEN: Git operation' }
function winget { throw 'FORBIDDEN: package operation' }
'@ | Add-Content -LiteralPath (Join-Path $fixtureRoot 'setup-scripts/setup-functions.ps1')
    }
    It 'preserves module order and package catalog order with equivalent duplicate IDs' {
        $bootstrap.INSTALL_PACKAGES = @('dev', 'base')
        $bootstrap.INSTALL_SETTINGS = @()
        Save-PlanBootstrap
        '{"base":["Vendor.First",{"id":"Vendor.Second","scope":"machine","installerType":"wix"}],"dev":["vendor.first","Vendor.Last"],"wsl":[],"pwsh":[]}' |
            Set-Content (Join-Path $configDirectory 'winget-packages.json')
        $preview = Get-DotfilesSetupPreview -RepositoryRoot $fixtureRoot
        ($preview.Packages.Id -join ',') | Should -Be 'Vendor.First,Vendor.Second,Vendor.Last'
        $preview.Packages[1].Scope | Should -Be 'machine'
        $preview.Packages[1].InstallerType | Should -Be 'wix'
        $expected = @(Get-DotfilesSetupPlan $bootstrap -ConfigDirectory $configDirectory)
        ($preview.Modules.Script -join ',') | Should -Be ($expected.Script -join ',')
        ($preview.Modules.Order -join ',') | Should -Be '1,2,3'
    }
    It 'preserves explicit empty selections in all collections' {
        foreach ($name in @('INSTALL_FEATURES', 'INSTALL_CAPABILITIES', 'INSTALL_PACKAGES', 'INSTALL_SETTINGS')) {
            $bootstrap.$name = @()
        }
        Save-PlanBootstrap
        $preview = Get-DotfilesSetupPreview -RepositoryRoot $fixtureRoot
        foreach ($name in @('Features', 'Capabilities', 'Packages', 'Modules')) {
            @($preview.$name) | Should -HaveCount 0
        }
        foreach ($selection in $preview.Selections.PSObject.Properties) {
            ($selection.Value -is [array]) | Should -BeTrue
            $selection.Value.Count | Should -Be 0
        }
    }
    It 'retains legacy defaults when selectors are missing' {
        foreach ($name in @('INSTALL_FEATURES', 'INSTALL_CAPABILITIES', 'INSTALL_PACKAGES', 'INSTALL_SETTINGS')) {
            $bootstrap.PSObject.Properties.Remove($name)
        }
        Save-PlanBootstrap
        $preview = Get-DotfilesSetupPreview -RepositoryRoot $fixtureRoot
        $preview.Capabilities | Should -HaveCount 0
        $preview.Packages.Count | Should -BeGreaterThan 0
        ($preview.Modules.Script -join ',') | Should -Be (@(Get-DotfilesSetupPlan $bootstrap -ConfigDirectory $configDirectory).Script -join ',')
    }
    It 'handles legacy scalar selectors and marks conditional elevation and restart' {
        $bootstrap.INSTALL_PACKAGES = 'base'
        $bootstrap.INSTALL_SETTINGS = 'base'
        Save-PlanBootstrap
        '{"TEST_PRIVATE":{"Value":"do-not-print-env","Scope":"Machine"}}' | Set-Content (Join-Path $configDirectory 'env-variables.json')
        $preview = Get-DotfilesSetupPreview -RepositoryRoot $fixtureRoot
        @($preview.Selections.Packages) | Should -HaveCount 1
        ($preview.Modules | Where-Object Script -eq 'Set-EnvironmentVariables.ps1').Elevation | Should -BeLike '*Machine*'
        ($preview.Modules | Where-Object Script -eq 'Configure-WindowsFeatures.ps1').MayRequireRestart | Should -BeTrue
        ($preview.Modules | Where-Object Script -eq 'Set-UserHomeAlias.ps1').RequiresAdmin | Should -BeTrue
    }
    It 'produces standalone JSON without mutations or private values in PowerShell 7 and Windows PowerShell 5.1' {
        $bootstrap.REPOSITORY_ENDPOINT_TYPE = 'custom'
        $bootstrap.CUSTOM_REPOSITORY_URL = 'https://do-not-print-repository.example/repo.git'
        Save-PlanBootstrap
        '{"user.name":"do-not-print-git"}' | Set-Content (Join-Path $configDirectory 'git-variables.json')
        '{"TEST_PRIVATE":{"Value":"do-not-print-env","Scope":"User"}}' | Set-Content (Join-Path $configDirectory 'env-variables.json')
        $before = Get-PlanFixtureSnapshot
        foreach ($hostPath in $hosts) {
            $output = & $hostPath -NoProfile -File "$fixtureRoot/setup-scripts/setup.ps1" -Plan -PlanFormat Json -BootstrapBranch preview-branch -NonInteractive 2>&1
            $LASTEXITCODE | Should -Be 0
            $text = $output -join "`n"
            $text | Should -Not -Match 'FORBIDDEN|do-not-print'
            $parsed = $text | ConvertFrom-Json
            $parsed.SchemaVersion | Should -Be 1
            $parsed.Branch | Should -Be 'preview-branch'
            $parsed.Modules.Count | Should -BeGreaterThan 0
            ($parsed.Packages -is [array]) | Should -BeTrue
            Get-PlanFixtureSnapshot | Should -Be $before
            Test-Path (Join-Path $fixtureRoot 'logs') | Should -BeFalse
        }
    }
    It 'shows readable output without mutations in both supported entry hosts' {
        $before = Get-PlanFixtureSnapshot
        foreach ($hostPath in $hosts) {
            $output = & $hostPath -NoProfile -File "$fixtureRoot/setup-scripts/setup.ps1" -Plan 2>&1
            $LASTEXITCODE | Should -Be 0
            ($output -join "`n") | Should -Match 'SETUP PLAN \(read-only\)'
            ($output -join "`n") | Should -Match 'Modules \(execution order\)'
            Get-PlanFixtureSnapshot | Should -Be $before
        }
    }
    It 'fails invalid configuration before any mutation in both hosts' {
        $bootstrap.INSTALL_PACKAGES = @('typo')
        Save-PlanBootstrap
        $before = Get-PlanFixtureSnapshot
        foreach ($hostPath in $hosts) {
            $output = & $hostPath -NoProfile -File "$fixtureRoot/setup-scripts/setup.ps1" -Plan -PlanFormat Json 2>&1
            $LASTEXITCODE | Should -Be 1
            ($output -join "`n") | Should -Match "Unknown selection 'typo'"
            ($output -join "`n") | Should -Not -Match 'FORBIDDEN'
            Get-PlanFixtureSnapshot | Should -Be $before
        }
    }
    It 'fails missing configuration without generating defaults in both hosts' {
        Remove-Item -LiteralPath $bootstrapPath
        $before = Get-PlanFixtureSnapshot
        foreach ($hostPath in $hosts) {
            $output = & $hostPath -NoProfile -File "$fixtureRoot/setup-scripts/setup.ps1" -Plan -NonInteractive 2>&1
            $LASTEXITCODE | Should -Be 1
            ($output -join "`n") | Should -Match 'configure.ps1'
            ($output -join "`n") | Should -Not -Match 'FORBIDDEN'
            Get-PlanFixtureSnapshot | Should -Be $before
        }
    }
    It 'applies an invocation-only branch override when the saved branch is absent' {
        $bootstrap.PSObject.Properties.Remove('GITHUB_DOTFILES_BRANCH')
        Save-PlanBootstrap
        (Get-DotfilesSetupPreview -RepositoryRoot $fixtureRoot -BootstrapBranch preview-branch).Branch | Should -Be 'preview-branch'
        (Read-DotfilesConfigurationObject $bootstrapPath).PSObject.Properties.Name | Should -Not -Contain 'GITHUB_DOTFILES_BRANCH'
    }
    It 'keeps empty and singleton collections as JSON arrays in both hosts and ignores log arguments' {
        foreach ($name in @('INSTALL_FEATURES', 'INSTALL_CAPABILITIES', 'INSTALL_PACKAGES', 'INSTALL_SETTINGS')) {
            $bootstrap.$name = @()
        }
        $bootstrap.INSTALL_PACKAGES = 'base'
        Save-PlanBootstrap
        '{"base":["Vendor.Only"],"dev":[],"wsl":[],"pwsh":[]}' | Set-Content (Join-Path $configDirectory 'winget-packages.json')
        $before = Get-PlanFixtureSnapshot
        foreach ($hostPath in $hosts) {
            $output = & $hostPath -NoProfile -File "$fixtureRoot/setup-scripts/setup.ps1" -Plan -PlanFormat Json `
                -LogFilePath "$fixtureRoot/should-not-exist.txt" -AppendLog 2>&1
            $LASTEXITCODE | Should -Be 0
            $parsed = ($output -join "`n") | ConvertFrom-Json
            foreach ($name in @('Features', 'Capabilities', 'Packages', 'Modules')) {
                ($parsed.$name -is [array]) | Should -BeTrue
            }
            foreach ($selection in $parsed.Selections.PSObject.Properties) {
                ($selection.Value -is [array]) | Should -BeTrue
            }
            $parsed.Packages.Count | Should -Be 1
            $parsed.Modules.Count | Should -Be 1
            Get-PlanFixtureSnapshot | Should -Be $before
        }
    }
    It 'rejects PlanFormat without Plan before reaching apply in both hosts' {
        $before = Get-PlanFixtureSnapshot
        foreach ($hostPath in $hosts) {
            $output = & $hostPath -NoProfile -File "$fixtureRoot/setup-scripts/setup.ps1" -PlanFormat Json 2>&1
            $LASTEXITCODE | Should -Be 1
            ($output -join "`n") | Should -Match '-PlanFormat requires -Plan'
            ($output -join "`n") | Should -Not -Match 'FORBIDDEN'
            Get-PlanFixtureSnapshot | Should -Be $before
        }
    }
    It 'rejects an invalid saved branch even with a valid invocation override in both hosts' {
        $bootstrap.GITHUB_DOTFILES_BRANCH = 42
        Save-PlanBootstrap
        $before = Get-PlanFixtureSnapshot
        foreach ($hostPath in $hosts) {
            $output = & $hostPath -NoProfile -File "$fixtureRoot/setup-scripts/setup.ps1" -Plan -PlanFormat Json `
                -BootstrapBranch preview-branch 2>&1
            $LASTEXITCODE | Should -Be 1
            ($output -join "`n") | Should -Match 'GITHUB_DOTFILES_BRANCH must be a string'
            ($output -join "`n") | Should -Not -Match 'FORBIDDEN'
            Get-PlanFixtureSnapshot | Should -Be $before
        }
    }
}
