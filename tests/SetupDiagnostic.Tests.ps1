Describe 'Installed-state diagnostic' {
    BeforeAll {
        $repositoryRoot = Split-Path -Parent $PSScriptRoot
        . "$repositoryRoot/setup-scripts/setup-functions.ps1"
        . "$repositoryRoot/setup-scripts/setup-plan.ps1"
        . "$repositoryRoot/setup-scripts/verify-functions.ps1"
        function Get-TestDiagnostic {
            Get-DotfilesSetupDiagnostic -RepositoryRoot $TestDrive -LocalAppData $TestDrive -UserProfile $TestDrive -ProfileDirectory $TestDrive
        }
    }
    BeforeEach {
        $script:diagnosticFixturePreview = [pscustomobject]@{ Features=@(); Capabilities=@(); Packages=@(); Modules=@() }
        Mock Get-DotfilesSetupPreview { $script:diagnosticFixturePreview }
        Mock Get-Command { [pscustomobject]@{ Source='fixture.exe' } } -ParameterFilter { $Name -in @('pwsh', 'git', 'winget') }
    }
    It 'reports empty selections without calling apply or initializing configuration' {
        Mock Initialize-DotfilesConfiguration { throw 'Mutation attempted' }
        Mock Start-Logging { throw 'Mutation attempted' }
        $report = Get-TestDiagnostic
        $report.ExitCode | Should -Be 0
        $report.Counts.Skipped | Should -Be 1
        Should -Invoke Initialize-DotfilesConfiguration -Times 0 -Exactly
        Should -Invoke Start-Logging -Times 0 -Exactly
    }
    It 'stops probes on invalid configuration and redacts exception details' {
        Mock Get-DotfilesSetupPreview { throw 'private-secret' }
        $report = Get-TestDiagnostic
        $report.ExitCode | Should -Be 2
        $report.Checks | Should -HaveCount 1
        ($report | ConvertTo-Json -Depth 8) | Should -Not -Match 'private-secret'
    }
    It 'does not require or query missing WinGet when package setup is deselected' {
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'winget' }
        Mock Invoke-DotfilesDiagnosticNative { throw 'Unexpected native query' }
        $report = Get-TestDiagnostic
        $report.ExitCode | Should -Be 0
        @($report.Checks | Where-Object Name -EQ winget) | Should -HaveCount 0
        Should -Invoke Get-Command -Times 0 -Exactly -ParameterFilter { $Name -eq 'winget' }
        Should -Invoke Invoke-DotfilesDiagnosticNative -Times 0 -Exactly
    }
    It 'reports missing WinGet as drift when package setup is selected without query opt-in' {
        $script:diagnosticFixturePreview.Modules = @([pscustomobject]@{Script='Install-WingetPackages.ps1'})
        $script:diagnosticFixturePreview.Packages = @([pscustomobject]@{Id='Vendor.App';Scope=$null;InstallerType=$null})
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'winget' }
        Mock Invoke-DotfilesDiagnosticNative { throw 'Unexpected native query' }
        $report = Get-TestDiagnostic
        ($report.Checks | Where-Object Name -EQ winget).Status | Should -Be Drift
        $report.ExitCode | Should -Be 1
        Should -Invoke Invoke-DotfilesDiagnosticNative -Times 0 -Exactly
    }
    It 'distinguishes enabled, disabled, absent and indeterminate Windows features' {
        $script:diagnosticFixturePreview.Features = @('Enabled', 'Disabled', 'Absent', 'Indeterminate', 'Unavailable')
        Mock Get-CimInstance { @(
            [pscustomobject]@{Name='Enabled';InstallState=1},
            [pscustomobject]@{Name='Disabled';InstallState=2},
            [pscustomobject]@{Name='Absent';InstallState=3},
            [pscustomobject]@{Name='Indeterminate';InstallState=4}) }
        $report = Get-TestDiagnostic
        ($report.Checks | Where-Object Category -EQ WindowsFeature).Status -join ',' | Should -Be 'Passed,Drift,Drift,Unknown,Unknown'
        $report.ExitCode | Should -Be 1
    }
    It 'keeps denied feature queries inconclusive' {
        $script:diagnosticFixturePreview.Features = @('Enabled')
        Mock Get-CimInstance { throw 'private-secret' }
        $report = Get-TestDiagnostic
        $report.ExitCode | Should -Be 2
        ($report.Checks | Where-Object Category -EQ WindowsFeature).Status | Should -Be Unknown
    }
    It 'distinguishes installed, absent and pending Windows capabilities' {
        $script:diagnosticFixturePreview.Capabilities = @('Installed', 'NotPresent', 'Staged', 'InstallPending', 'UninstallPending', 'Denied')
        Mock Get-WindowsCapability {
            if ($Name -eq 'Denied') { throw 'private-secret' }
            [pscustomobject]@{State=$Name}
        }
        $report = Get-TestDiagnostic
        ($report.Checks | Where-Object Category -EQ WindowsCapability).Status -join ',' | Should -Be 'Passed,Drift,Drift,Unknown,Unknown,Unknown'
        ($report | ConvertTo-Json -Depth 8) | Should -Not -Match 'private-secret'
    }
    It 'returns drift exit code when a staged capability is the only mismatch' {
        $script:diagnosticFixturePreview.Capabilities = @('Fixture.Capability')
        Mock Get-WindowsCapability { [pscustomobject]@{State='Staged'} }
        $report = Get-TestDiagnostic
        ($report.Checks | Where-Object Category -EQ WindowsCapability).Status | Should -Be Drift
        $report.ExitCode | Should -Be 1
        $report.Counts.Drift | Should -Be 1
        $report.Counts.Unknown | Should -Be 0
    }
    It 'compares persistent environment values without exposing names or values' {
        $script:diagnosticFixturePreview.Modules = @([pscustomobject]@{Script='Set-EnvironmentVariables.ps1'})
        Mock Read-DotfilesConfigurationObject { [pscustomobject]@{EnvironmentVariables=@(
            [pscustomobject]@{Name='private-name';Value='private-value';Scope='User'},
            [pscustomobject]@{Name='other';Value='expected';Scope='Machine'})} }
        Mock Get-DotfilesDiagnosticEnvironmentValue { if ($Scope -eq 'User') { 'private-value' } else { 'different' } }
        $report = Get-TestDiagnostic
        ($report.Checks | Where-Object Category -EQ Environment).Status -join ',' | Should -Be 'Passed,Drift'
        ($report | ConvertTo-Json -Depth 8) | Should -Not -Match 'private-name|private-value|different|expected'
    }
    It 'checks Git using bounded read queries and detects missing or repeated values' {
        $script:diagnosticFixturePreview.Modules = @([pscustomobject]@{Script='Apply-GitConfig.ps1'})
        Mock Read-DotfilesConfigurationObject { [pscustomobject]@{'user.name'='private-value';'core.editor'='editor';'core.autocrlf'='true';'user.email'=''} }
        Mock Invoke-DotfilesDiagnosticNative {
            switch ($Arguments[-1]) {
                'user.name' { [pscustomobject]@{ExitCode=0;Output="private-value`n"} }
                'core.editor' { [pscustomobject]@{ExitCode=1;Output=''} }
                default { [pscustomobject]@{ExitCode=0;Output="true`nfalse`n"} }
            }
        }
        $report = Get-TestDiagnostic
        ($report.Checks | Where-Object Category -EQ Git).Status -join ',' | Should -Be 'Passed,Drift,Drift,Skipped'
        ($report | ConvertTo-Json -Depth 8) | Should -Not -Match 'private-value|user.name|user.email'
        Should -Invoke Invoke-DotfilesDiagnosticNative -Times 3 -Exactly -ParameterFilter { $Command -eq 'git' -and ($Arguments[0..3] -join ' ') -eq 'config --global --get-all --' }
    }
    It 'treats an absent persistent environment variable as the configured empty value' {
        $script:diagnosticFixturePreview.Modules = @([pscustomobject]@{Script='Set-EnvironmentVariables.ps1'})
        Mock Read-DotfilesConfigurationObject { [pscustomobject]@{EnvironmentVariables=@([pscustomobject]@{Name='fixture';Value='';Scope='User'})} }
        Mock Get-DotfilesDiagnosticEnvironmentValue { $null }
        ((Get-TestDiagnostic).Checks | Where-Object Category -EQ Environment).Status | Should -Be Passed
    }
    It 'makes package queries opt-in and does not infer absence from native failure' {
        $script:diagnosticFixturePreview.Modules = @([pscustomobject]@{Script='Install-WingetPackages.ps1'})
        $script:diagnosticFixturePreview.Packages = @([pscustomobject]@{Id='Vendor.App';Scope=$null;InstallerType=$null})
        Mock Invoke-DotfilesDiagnosticNative { [pscustomobject]@{ExitCode=1;Output='private-secret'} }
        (Get-TestDiagnostic).ExitCode | Should -Be 2
        Should -Invoke Invoke-DotfilesDiagnosticNative -Times 0 -Exactly
        $report = Get-DotfilesSetupDiagnostic -RepositoryRoot $TestDrive -CheckPackages
        ($report.Checks | Where-Object Category -EQ Package).Status | Should -Be Unknown
        Should -Invoke Invoke-DotfilesDiagnosticNative -Times 1 -Exactly -ParameterFilter { $Command -eq 'winget' -and ($Arguments -join ' ') -eq 'list --id Vendor.App --exact --source winget --disable-interactivity' }
    }
    It 'detects an additional empty Git entry rather than trimming it away' {
        $script:diagnosticFixturePreview.Modules = @([pscustomobject]@{Script='Apply-GitConfig.ps1'})
        Mock Read-DotfilesConfigurationObject { [pscustomobject]@{'user.name'='fixture'} }
        Mock Invoke-DotfilesDiagnosticNative { [pscustomobject]@{ExitCode=0;Output="fixture`n`n"} }
        ((Get-TestDiagnostic).Checks | Where-Object Category -EQ Git).Status | Should -Be Drift
    }
    It 'requires observable exact package ID evidence even when WinGet exits successfully' {
        $script:diagnosticFixturePreview.Modules = @([pscustomobject]@{Script='Install-WingetPackages.ps1'})
        $script:diagnosticFixturePreview.Packages = @([pscustomobject]@{Id='Vendor.App';Scope=$null;InstallerType=$null})
        Mock Invoke-DotfilesDiagnosticNative { [pscustomobject]@{ExitCode=0;Output='Vendor.App.Extension'} }
        $report = Get-DotfilesSetupDiagnostic -RepositoryRoot $TestDrive -CheckPackages
        ($report.Checks | Where-Object Category -EQ Package).Status | Should -Be Unknown
        Mock Invoke-DotfilesDiagnosticNative { [pscustomobject]@{ExitCode=0;Output='App  Vendor.App  1.0  winget'} }
        $report = Get-DotfilesSetupDiagnostic -RepositoryRoot $TestDrive -CheckPackages
        ($report.Checks | Where-Object Category -EQ Package).Status | Should -Be Passed
    }
    It 'certifies package scope only through the requested scope filter' {
        $script:diagnosticFixturePreview.Modules = @([pscustomobject]@{Script='Install-WingetPackages.ps1'})
        $script:diagnosticFixturePreview.Packages = @([pscustomobject]@{Id='Vendor.App';Scope='machine';InstallerType=$null})
        Mock Invoke-DotfilesDiagnosticNative { [pscustomobject]@{ExitCode=0;Output='Vendor.App'} }
        $report = Get-DotfilesSetupDiagnostic -RepositoryRoot $TestDrive -CheckPackages
        ($report.Checks | Where-Object Category -EQ Package).Status | Should -Be Passed
        Should -Invoke Invoke-DotfilesDiagnosticNative -Times 1 -Exactly -ParameterFilter { $Arguments -contains '--scope' -and $Arguments -contains 'machine' }
    }
    It 'keeps installer type inconclusive even when requested scope matches' {
        $script:diagnosticFixturePreview.Modules = @([pscustomobject]@{Script='Install-WingetPackages.ps1'})
        $script:diagnosticFixturePreview.Packages = @([pscustomobject]@{Id='Vendor.App';Scope='machine';InstallerType='wix'})
        Mock Invoke-DotfilesDiagnosticNative { [pscustomobject]@{ExitCode=0;Output='Vendor.App'} }
        $report = Get-DotfilesSetupDiagnostic -RepositoryRoot $TestDrive -CheckPackages
        ($report.Checks | Where-Object Category -EQ Package).Status | Should -Be Unknown
    }
    It 'reports package drift for <State> without accepting agreements' -ForEach @(
        @{ State = 'Missing' }, @{ State = 'ScopeMismatch' }
    ) {
        $script:diagnosticFixturePreview.Modules = @([pscustomobject]@{Script='Install-WingetPackages.ps1'})
        $script:diagnosticFixturePreview.Packages = @([pscustomobject]@{Id='Vendor.App';Scope='machine';InstallerType=$null})
        Mock Invoke-DotfilesDiagnosticNative {
            param($Arguments)
            if ($Arguments -contains '--scope' -or $State -eq 'Missing') { [pscustomobject]@{ ExitCode = -1978335212; Output = '' } }
            else { [pscustomobject]@{ ExitCode = 0; Output = 'Vendor.App' } }
        }
        $report = Get-DotfilesSetupDiagnostic -RepositoryRoot $TestDrive -CheckPackages
        ($report.Checks | Where-Object Category -EQ Package).Status | Should -Be Drift
        $report.ExitCode | Should -Be 1
        Should -Invoke Invoke-DotfilesDiagnosticNative -Times 0 -Exactly -ParameterFilter { $Arguments -contains '--accept-source-agreements' }
    }
    It 'never silently passes unsupported modules or missing source inventories' {
        $script:diagnosticFixturePreview.Modules = @([pscustomobject]@{Script='Install-NerdFont.ps1'}, [pscustomobject]@{Script='Install-LocalPowerShellProfiles.ps1'}, [pscustomobject]@{Script='Install-OmpConfig.ps1'})
        $report = Get-TestDiagnostic
        $report.Counts.Unknown | Should -Be 3
        $report.ExitCode | Should -Be 2
    }
    It 'detects file drift without changing either file' {
        $source = Join-Path $TestDrive 'source.json'
        $target = Join-Path $TestDrive 'target.json'
        '{}' | Set-Content $source
        (Test-DotfilesDiagnosticFile $source $target).Status | Should -Be Drift
        Copy-Item $source $target
        (Test-DotfilesDiagnosticFile $source $target).Status | Should -Be Passed
        '{"custom":true}' | Set-Content $target
        $before = (Get-FileHash $target).Hash
        (Test-DotfilesDiagnosticFile $source $target).Status | Should -Be Drift
        (Get-FileHash $target).Hash | Should -Be $before
    }
    It 'checks managed portable stubs and preserves user-authored profiles' {
        $script:diagnosticFixturePreview.Modules = @([pscustomobject]@{Script='Install-LocalPowerShellProfiles.ps1'})
        $sourceDirectory = Join-Path $TestDrive 'powershell-profiles'
        $copyDirectory = Join-Path $TestDrive 'dotfiles/powershell-profiles'
        New-Item -ItemType Directory $sourceDirectory, $copyDirectory -Force | Out-Null
        '# source' | Set-Content "$sourceDirectory/Microsoft.PowerShell_profile.ps1"
        Copy-Item "$sourceDirectory/Microsoft.PowerShell_profile.ps1" "$copyDirectory/Microsoft.PowerShell_profile.ps1"
        $stub = Join-Path $TestDrive 'Microsoft.PowerShell_profile.ps1'
        $marker = '# dotfiles-managed stub - real profile lives in LOCALAPPDATA. Do not edit this file.'
        @($marker, '$localProfile = Join-Path $env:LOCALAPPDATA ''dotfiles\powershell-profiles\Microsoft.PowerShell_profile.ps1''', 'if (Test-Path -LiteralPath $localProfile -PathType Leaf) { . $localProfile }') | Set-Content $stub
        ((Get-TestDiagnostic).Checks | Where-Object Category -EQ ProfileStub).Status | Should -Be Passed
        '# personal profile' | Set-Content $stub
        ((Get-TestDiagnostic).Checks | Where-Object Category -EQ ProfileStub).Status | Should -Be Skipped
        (Get-Content $stub) | Should -Be '# personal profile'
        $marker | Set-Content $stub
        ((Get-TestDiagnostic).Checks | Where-Object Category -EQ ProfileStub).Status | Should -Be Drift
    }
    It 'checks shared profile support copies without requiring host stubs for them' {
        $script:diagnosticFixturePreview.Modules = @([pscustomobject]@{Script='Install-LocalPowerShellProfiles.ps1'})
        $sourceDirectory = Join-Path $TestDrive 'powershell-profiles'
        $copyDirectory = Join-Path $TestDrive 'dotfiles/powershell-profiles'
        New-Item -ItemType Directory $sourceDirectory, $copyDirectory -Force | Out-Null
        '# shared' | Set-Content "$sourceDirectory/common.ps1"
        Copy-Item "$sourceDirectory/common.ps1" "$copyDirectory/common.ps1"
        $checks = (Get-TestDiagnostic).Checks
        ($checks | Where-Object { $_.Category -eq 'ProfileCopy' -and $_.Name -eq 'common.ps1' }).Status | Should -Be Passed
        @($checks | Where-Object { $_.Category -eq 'ProfileStub' -and $_.Name -eq 'common.ps1' }) | Should -HaveCount 0
        ($checks | Where-Object Category -EQ ProfileSupportStub).Status | Should -Be Passed
        '# dotfiles-managed stub - real profile lives in LOCALAPPDATA. Do not edit this file.' | Set-Content "$TestDrive/common.ps1"
        ((Get-TestDiagnostic).Checks | Where-Object Category -EQ ProfileSupportStub).Status | Should -Be Drift
        '# personal' | Set-Content "$TestDrive/common.ps1"
        ((Get-TestDiagnostic).Checks | Where-Object Category -EQ ProfileSupportStub).Status | Should -Be Skipped
        '# outdated' | Set-Content "$copyDirectory/common.ps1"
        ((Get-TestDiagnostic).Checks | Where-Object { $_.Category -eq 'ProfileCopy' -and $_.Name -eq 'common.ps1' }).Status | Should -Be Drift
    }
    It 'reports an obsolete support stub even when its optional source no longer exists' {
        $script:diagnosticFixturePreview.Modules = @([pscustomobject]@{Script='Install-LocalPowerShellProfiles.ps1'})
        '# dotfiles-managed stub - real profile lives in LOCALAPPDATA. Do not edit this file.' | Set-Content "$TestDrive/retired.ps1"
        $checks = (Get-TestDiagnostic).Checks
        ($checks | Where-Object { $_.Category -eq 'ProfileSupportStub' -and $_.Name -eq 'retired.ps1' }).Status | Should -Be Drift
        @($checks | Where-Object { $_.Category -eq 'ProfileCopy' -and $_.Name -eq 'retired.ps1' }) | Should -HaveCount 0
    }
    It 'reports an identical linked theme as drift until it is detached' {
        $source = Join-Path $TestDrive 'linked-source.json'
        $target = Join-Path $TestDrive 'linked-target.json'
        '{}' | Set-Content $source
        New-Item -ItemType HardLink -Path $target -Value $source | Out-Null
        (Test-DotfilesDiagnosticFile $source $target -RequireIndependent).Status | Should -Be Drift
        . "$repositoryRoot/setup-scripts/deployment-functions.ps1"
        Copy-DotfilesVerifiedFile $source $target | Out-Null
        (Test-DotfilesDiagnosticFile $source $target -RequireIndependent).Status | Should -Be Passed
    }
    It 'allows customized Terminal JSON without claiming template equality' {
        $script:diagnosticFixturePreview.Modules = @([pscustomobject]@{Script='Install-WindowsTerminalSettings.ps1'})
        $directory = Join-Path $TestDrive 'Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState'
        New-Item -ItemType Directory $directory -Force | Out-Null
        '{"custom":true}' | Set-Content "$directory/settings.json"
        ((Get-TestDiagnostic).Checks | Where-Object Category -EQ Terminal).Status | Should -Be Passed
        '{invalid}' | Set-Content "$directory/settings.json"
        $report = Get-TestDiagnostic
        ($report.Checks | Where-Object Category -EQ Terminal).Status | Should -Be Drift
        $report.ExitCode | Should -Be 1
        ($report | ConvertTo-Json -Depth 8) | Should -Not -Match '\{invalid\}|Unexpected character'
        '' | Set-Content "$directory/settings.json"
        ((Get-TestDiagnostic).Checks | Where-Object Category -EQ Terminal).Status | Should -Be Drift
    }
    It 'keeps Terminal access and read failures inconclusive without leaking error details' {
        $script:diagnosticFixturePreview.Modules = @([pscustomobject]@{Script='Install-WindowsTerminalSettings.ps1'})
        $directory = Join-Path $TestDrive 'Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState'
        New-Item -ItemType Directory $directory -Force | Out-Null
        '{"custom":true}' | Set-Content "$directory/settings.json"
        Mock Get-Content { throw [UnauthorizedAccessException]::new('private-secret') } -ParameterFilter { $LiteralPath -like '*LocalState*settings.json' }
        $report = Get-TestDiagnostic
        ($report.Checks | Where-Object Category -EQ Terminal).Status | Should -Be Unknown
        $report.ExitCode | Should -Be 2
        ($report | ConvertTo-Json -Depth 8) | Should -Not -Match 'private-secret'
        Mock Get-Content { throw [IO.IOException]::new('private-read-error') } -ParameterFilter { $LiteralPath -like '*LocalState*settings.json' }
        $report = Get-TestDiagnostic
        ($report.Checks | Where-Object Category -EQ Terminal).Status | Should -Be Unknown
        $report.ExitCode | Should -Be 2
        ($report | ConvertTo-Json -Depth 8) | Should -Not -Match 'private-read-error'
    }
    It 'bounds native execution and captures stderr without returning it' {
        # Use the real application resolver for the subprocess contract.
        Mock Get-Command { [pscustomobject]@{Source=(Join-Path $PSHOME 'pwsh.exe')} } -ParameterFilter { $Name -in @('pwsh', 'git', 'winget') }
        $query = Invoke-DotfilesDiagnosticNative pwsh @('-NoProfile', '-Command', '[Console]::Error.WriteLine("private-secret"); [Console]::WriteLine("fixture"); exit 3')
        $query.ExitCode | Should -Be 3
        $query.Output.Trim() | Should -Be fixture
        ($query | ConvertTo-Json) | Should -Not -Match 'private-secret'
        { Invoke-DotfilesDiagnosticNative pwsh @('-NoProfile', '-Command', 'Start-Sleep -Seconds 10') -TimeoutMilliseconds 100 } | Should -Throw '*timed out*'
    }
    It 'emits standalone CLI JSON and preserves configuration without apply side effects' {
        $fixture = Join-Path $TestDrive 'cli'
        $configuration = Join-Path $fixture 'dotfiles-configurations'
        New-Item -ItemType Directory $configuration -Force | Out-Null
        Copy-Item "$repositoryRoot/setup-scripts" $fixture -Recurse
        Copy-Item "$repositoryRoot/setup-modules" $fixture -Recurse
        foreach ($file in Get-ChildItem "$repositoryRoot/dotfiles-configurations/*.json.example") {
            Copy-Item $file.FullName (Join-Path $configuration ($file.Name -replace '\.example$', ''))
        }
        $bootstrapPath = Join-Path $configuration 'dotfiles-bootstrap-variables.json'
        $bootstrap = Read-DotfilesConfigurationObject $bootstrapPath
        foreach ($name in @('INSTALL_FEATURES', 'INSTALL_CAPABILITIES', 'INSTALL_PACKAGES', 'INSTALL_SETTINGS')) { $bootstrap.$name = @() }
        $bootstrap | ConvertTo-Json -Depth 20 | Set-Content $bootstrapPath
        @'
function Initialize-DotfilesConfiguration { throw 'FORBIDDEN: initialization' }
function Start-Logging { throw 'FORBIDDEN: logging' }
function Install-DotfilesPrerequisites { throw 'FORBIDDEN: installation' }
function Sync-DotfilesLocalConfiguration { throw 'FORBIDDEN: sync' }
function Start-Process { throw 'FORBIDDEN: elevation' }
'@ | Add-Content "$fixture/setup-scripts/setup-functions.ps1"
        # Stable prerequisite results, without depending on the CI machine's package state.
        'function Get-Command { [pscustomobject]@{Source="fixture.exe"} }' | Add-Content "$fixture/setup-scripts/verify-functions.ps1"
        $before = @(Get-ChildItem $fixture -Recurse -File | Sort-Object FullName | Get-FileHash).Hash -join ','
        $hostPath = Join-Path $PSHOME 'pwsh.exe'
        $output = & $hostPath -NoProfile -File "$fixture/setup-scripts/verify.ps1" -Format Json 2>&1
        $LASTEXITCODE | Should -Be 0
        $report = ($output -join "`n") | ConvertFrom-Json
        $report.SchemaVersion | Should -Be 1
        $report.ExitCode | Should -Be 0
        (@(Get-ChildItem $fixture -Recurse -File | Sort-Object FullName | Get-FileHash).Hash -join ',') | Should -Be $before
        Test-Path "$fixture/logs" | Should -BeFalse
        '{invalid}' | Set-Content $bootstrapPath
        $output = & $hostPath -NoProfile -File "$fixture/setup-scripts/verify.ps1" -Format Json 2>&1
        $LASTEXITCODE | Should -Be 2
        (($output -join "`n") | ConvertFrom-Json).Counts.Unknown | Should -Be 1
    }
}
