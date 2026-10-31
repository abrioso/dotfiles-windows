Describe 'Retired provisioning entry points' {
    BeforeAll {
        $repositoryRoot = Split-Path -Parent $PSScriptRoot
        $hostPaths = @((Join-Path $PSHOME 'pwsh.exe'), "$env:SystemRoot/System32/WindowsPowerShell/v1.0/powershell.exe")
        $fixtureRoot = Join-Path $TestDrive 'legacy'
        New-Item -ItemType Directory $fixtureRoot | Out-Null
        $personalProfile = Join-Path $fixtureRoot 'personal-profile.ps1'
        '# private-profile-content' | Set-Content $personalProfile
        $profileHash = (Get-FileHash $personalProfile).Hash
        $harness = Join-Path $fixtureRoot 'invoke-legacy.ps1'
        @'
param([string]$EntryPath, [string]$PersonalProfile)
$ErrorActionPreference = 'Stop'
$PROFILE = $PersonalProfile
function winget { throw 'FORBIDDEN package mutation' }
function wsl { throw 'FORBIDDEN WSL mutation' }
function oh-my-posh { throw 'FORBIDDEN font mutation' }
function New-Item { throw 'FORBIDDEN filesystem mutation' }
function Remove-Item { throw 'FORBIDDEN filesystem mutation' }
function Copy-Item { throw 'FORBIDDEN filesystem mutation' }
function Set-Content { throw 'FORBIDDEN filesystem mutation' }
function Set-ItemProperty { throw 'FORBIDDEN registry mutation' }
function Enable-WindowsOptionalFeature { throw 'FORBIDDEN feature mutation' }
function Add-LocalGroupMember { throw 'FORBIDDEN membership mutation' }
function Invoke-WebRequest { throw 'FORBIDDEN download' }
function Install-Module { throw 'FORBIDDEN module installation' }
function Start-Process { throw 'FORBIDDEN process or elevation' }
. $EntryPath
'@ | Set-Content $harness
    }
    It 'rejects <Name> with migration guidance before provisioning in both entry hosts' -ForEach @(
        @{Name='06.base.configuration.user.ps1'},
        @{Name='07.pwsh.terminal.configuration.user.ps1'},
        @{Name='09.developer.configuration.user.ps1'},
        @{Name='2.hyperv.wsl.configuration.admin.ps1'},
        @{Name='3.docker.packages.admin.ps1'},
        @{Name='4.developer.configuration.admin.ps1'},
        @{Name='Apply-Env-Variables.ps1'},
        @{Name='Configure-OMP.ps1'},
        @{Name='Install-NerdFont.ps1'},
        @{Name='Install-Winget-Packages.ps1'}
    ) {
        foreach ($hostPath in $hostPaths) {
            $output = & $hostPath -NoProfile -File $harness -EntryPath "$repositoryRoot/powershell-scripts/$Name" -PersonalProfile $personalProfile 2>&1
            $LASTEXITCODE | Should -Be 1
            $text = $output -join "`n"
            $text | Should -Match 'Retired legacy entry point'
            $text | Should -Match 'powershell-scripts/README.md'
            $text | Should -Not -Match 'FORBIDDEN|private-profile-content'
            (Get-FileHash $personalProfile).Hash | Should -Be $profileHash
            @(Get-ChildItem $fixtureRoot -File) | Should -HaveCount 2
        }
    }
}

Describe 'Legacy diagnostic delegation' {
    BeforeAll {
        $repositoryRoot = Split-Path -Parent $PSScriptRoot
        $hostPath = Join-Path $PSHOME 'pwsh.exe'
    }
    BeforeEach {
        $fixtureRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $testsDirectory = Join-Path $fixtureRoot 'tests'
        $scriptDirectory = Join-Path $fixtureRoot 'setup-scripts'
        New-Item -ItemType Directory $testsDirectory, $scriptDirectory | Out-Null
        $wrapperPath = Join-Path $testsDirectory 'Verify-PowerShellProfiles.ps1'
        Copy-Item "$repositoryRoot/tests/Verify-PowerShellProfiles.ps1" $wrapperPath
        $diagnosticPath = Join-Path $scriptDirectory 'verify.ps1'
    }
    It 'forwards explicit options and preserves canonical exit code <Code> without a report file' -ForEach @(
        @{Code=0}, @{Code=1}, @{Code=2}
    ) {
        @"
param([string]`$Format='Text', [switch]`$CheckPackages)
[pscustomobject]@{Format=`$Format;CheckPackages=[bool]`$CheckPackages;ExitCode=$Code} | ConvertTo-Json
exit $Code
"@ | Set-Content $diagnosticPath
        $before = @(Get-ChildItem $fixtureRoot -Recurse -File | Sort-Object FullName | Get-FileHash).Hash -join ','
        $output = & $hostPath -NoProfile -File $wrapperPath -Format Json -CheckPackages 2>&1
        $LASTEXITCODE | Should -Be $Code
        $report = ($output -join "`n") | ConvertFrom-Json
        $report.Format | Should -Be Json
        $report.CheckPackages | Should -BeTrue
        $report.ExitCode | Should -Be $Code
        (@(Get-ChildItem $fixtureRoot -Recurse -File | Sort-Object FullName | Get-FileHash).Hash -join ',') | Should -Be $before
        Test-Path "$testsDirectory/Verify-PowerShellProfiles.results.json" | Should -BeFalse
    }
    It 'warns in text mode and does not opt into package queries by default' {
        'param([string]$Format="Text", [switch]$CheckPackages); "canonical-$Format-packages-$CheckPackages"; exit 0' | Set-Content $diagnosticPath
        $output = & $hostPath -NoProfile -File $wrapperPath 2>&1
        $LASTEXITCODE | Should -Be 0
        $text = $output -join "`n"
        $text | Should -Match 'Deprecated'
        $text | Should -Match 'canonical-Text-packages-False'
    }
    It 'fails when the canonical diagnostic is missing instead of returning stale success' {
        $output = & $hostPath -NoProfile -File $wrapperPath -Format Json 2>&1
        $LASTEXITCODE | Should -Be 1
        ($output -join "`n") | Should -Match 'canonical diagnostic could not run'
    }
    It 'matches real diagnostic JSON without exporting profile contents or changing local configuration' {
        Copy-Item "$repositoryRoot/setup-scripts/*" $scriptDirectory -Recurse
        Copy-Item "$repositoryRoot/setup-modules" $fixtureRoot -Recurse
        $configuration = Join-Path $fixtureRoot 'dotfiles-configurations'
        New-Item -ItemType Directory $configuration | Out-Null
        foreach ($file in Get-ChildItem "$repositoryRoot/dotfiles-configurations/*.json.example") {
            Copy-Item $file.FullName (Join-Path $configuration ($file.Name -replace '\.example$', ''))
        }
        $bootstrapPath = Join-Path $configuration 'dotfiles-bootstrap-variables.json'
        $bootstrap = Get-Content $bootstrapPath -Raw | ConvertFrom-Json
        foreach ($name in @('INSTALL_FEATURES', 'INSTALL_CAPABILITIES', 'INSTALL_PACKAGES', 'INSTALL_SETTINGS')) { $bootstrap.$name = @() }
        $bootstrap | ConvertTo-Json -Depth 20 | Set-Content $bootstrapPath
        '# private-profile-content' | Set-Content "$fixtureRoot/personal-profile.ps1"
        'function Get-Command { [pscustomobject]@{Source="fixture.exe"} }' | Add-Content "$scriptDirectory/verify-functions.ps1"
        $before = @(Get-ChildItem $fixtureRoot -Recurse -File | Sort-Object FullName | Get-FileHash).Hash -join ','
        $direct = & $hostPath -NoProfile -File $diagnosticPath -Format Json 2>&1
        $LASTEXITCODE | Should -Be 0
        $legacy = & $hostPath -NoProfile -File $wrapperPath -Format Json 2>&1
        $LASTEXITCODE | Should -Be 0
        ($legacy -join "`n") | Should -Be ($direct -join "`n")
        ($legacy -join "`n") | Should -Not -Match 'private-profile-content|Deprecated|OneDrive|results.json'
        (@(Get-ChildItem $fixtureRoot -Recurse -File | Sort-Object FullName | Get-FileHash).Hash -join ',') | Should -Be $before
        Test-Path "$testsDirectory/Verify-PowerShellProfiles.results.json" | Should -BeFalse
        Test-Path "$fixtureRoot/logs" | Should -BeFalse
    }
}
