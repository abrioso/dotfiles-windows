Describe 'Shared PowerShell host initialization' {
    BeforeAll {
        $repositoryRoot = Split-Path -Parent $PSScriptRoot
        # Define the optional executable so Pester can mock it even on a clean host.
        function oh-my-posh { param($Mode, $Shell, $ConfigFlag, $Config) }
    }
    BeforeEach {
        Mock Get-Module { $null } -ParameterFilter { $Name -eq 'Terminal-Icons' }
        Mock Import-Module { } -ParameterFilter { $Name -eq 'Terminal-Icons' }
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'oh-my-posh' }
        Mock oh-my-posh { '$script:sharedPromptLoaded = $true' }
        Mock Write-Warning { }
        $script:sharedPromptLoaded = $false
    }
    It 'loads <HostName> without optional tools' -ForEach @(
        @{ HostName = 'Microsoft.PowerShell_profile.ps1' }
        @{ HostName = 'Microsoft.VSCode_profile.ps1' }
    ) {
        . (Join-Path $repositoryRoot "powershell-profiles/$HostName")
        [Console]::OutputEncoding.CodePage | Should -Be 65001
        Should -Invoke Import-Module -Times 0 -Exactly
        Should -Invoke oh-my-posh -Times 0 -Exactly
    }
    It 'initializes the same optional tools from <HostName>' -ForEach @(
        @{ HostName = 'Microsoft.PowerShell_profile.ps1' }
        @{ HostName = 'Microsoft.VSCode_profile.ps1' }
    ) {
        Mock Get-Module { [pscustomobject]@{ Name = 'Terminal-Icons' } } -ParameterFilter { $Name -eq 'Terminal-Icons' }
        Mock Get-Command { [pscustomobject]@{ Name = 'oh-my-posh' } } -ParameterFilter { $Name -eq 'oh-my-posh' }
        Mock Test-Path { $true } -ParameterFilter { $Path -like '*jandedobbeleer.omp.json' }
        . (Join-Path $repositoryRoot "powershell-profiles/$HostName")
        $script:sharedPromptLoaded | Should -BeTrue
        Should -Invoke Import-Module -Times 1 -Exactly -ParameterFilter { $Name -eq 'Terminal-Icons' }
        Should -Invoke oh-my-posh -Times 1 -Exactly -ParameterFilter {
            $Mode -eq 'init' -and $Shell -eq 'pwsh' -and $ConfigFlag -eq '--config' -and $Config -eq "$env:USERPROFILE\.config\oh-my-posh\poshthemes\jandedobbeleer.omp.json"
        }
    }
    It 'warns when the optional prompt executable exists but its theme is missing' {
        Mock Get-Command { [pscustomobject]@{ Name = 'oh-my-posh' } } -ParameterFilter { $Name -eq 'oh-my-posh' }
        Mock Test-Path { $false } -ParameterFilter { $Path -like '*jandedobbeleer.omp.json' }
        . (Join-Path $repositoryRoot 'powershell-profiles/Microsoft.PowerShell_profile.ps1')
        Should -Invoke Write-Warning -Times 1 -Exactly -ParameterFilter { $Message -like '*Install-OmpConfig.ps1*' }
        Should -Invoke oh-my-posh -Times 0 -Exactly
    }
}

Describe 'Shared profile deployment integration' {
    BeforeAll { $repositoryRoot = Split-Path -Parent $PSScriptRoot }
    It 'deploys support files without stubs, preserves personal profiles and skips unchanged files' {
        $fixture = Join-Path $TestDrive 'profile-deployment'
        New-Item -ItemType Directory "$fixture/setup-scripts", "$fixture/setup-modules", "$fixture/powershell-profiles", "$fixture/documents" -Force | Out-Null
        Copy-Item "$repositoryRoot/setup-modules/Install-LocalPowerShellProfiles.ps1" "$fixture/setup-modules/Install-LocalPowerShellProfiles.ps1"
        Copy-Item "$repositoryRoot/powershell-profiles/*.ps1" "$fixture/powershell-profiles"
        '# private support' | Set-Content "$fixture/powershell-profiles/extra.ps1"
        '# personal profile' | Set-Content "$fixture/documents/Microsoft.VSCode_profile.ps1"
        @'
function Start-Logging { param($LogFilePath) }
function Stop-Logging { Add-Content (Join-Path $dotfileRootDir 'stopped.txt') 'stopped' }
function Write-Info { param($Message) }
function Write-ErrorMessage { param($Message) Write-Output $Message }
function Write-WarningMessage { param($Message) Write-Output $Message }
'@ | Set-Content "$fixture/setup-scripts/setup-functions.ps1"
        @'
param([string]$Root)
$env:LOCALAPPDATA = Join-Path $Root 'local'
$PROFILE = Join-Path $Root 'documents/Microsoft.PowerShell_profile.ps1'
$global:LASTEXITCODE = 0
& (Join-Path $Root 'setup-modules/Install-LocalPowerShellProfiles.ps1')
exit $LASTEXITCODE
'@ | Set-Content "$fixture/run.ps1"
        & (Join-Path $PSHOME 'pwsh') -NoProfile -File "$fixture/run.ps1" -Root $fixture
        $LASTEXITCODE | Should -Be 0
        $store = "$fixture/local/dotfiles/powershell-profiles"
        foreach ($file in Get-ChildItem "$fixture/powershell-profiles/*.ps1") {
            (Get-FileHash "$store/$($file.Name)").Hash | Should -Be (Get-FileHash $file.FullName).Hash
        }
        Get-Content "$fixture/documents/Microsoft.PowerShell_profile.ps1" -First 1 | Should -Match '^# dotfiles-managed stub'
        Get-Content "$fixture/documents/Microsoft.VSCode_profile.ps1" | Should -Be '# personal profile'
        Test-Path "$fixture/documents/common.ps1" | Should -BeFalse
        Test-Path "$fixture/documents/extra.ps1" | Should -BeFalse
        $stamp = [datetime]'2020-01-02T03:04:05Z'
        (Get-Item "$store/common.ps1").LastWriteTimeUtc = $stamp
        (Get-Item "$fixture/documents/Microsoft.PowerShell_profile.ps1").LastWriteTimeUtc = $stamp
        & (Join-Path $PSHOME 'pwsh') -NoProfile -File "$fixture/run.ps1" -Root $fixture
        $LASTEXITCODE | Should -Be 0
        (Get-Item "$store/common.ps1").LastWriteTimeUtc | Should -Be $stamp
        (Get-Item "$fixture/documents/Microsoft.PowerShell_profile.ps1").LastWriteTimeUtc | Should -Be $stamp
        @(Get-Content "$fixture/stopped.txt") | Should -HaveCount 2
        # Reapply a shared edit; both local host entry points still resolve it locally.
        '$script:localSharedLoaded = $PSScriptRoot' | Set-Content "$fixture/powershell-profiles/common.ps1"
        & (Join-Path $PSHOME 'pwsh') -NoProfile -File "$fixture/run.ps1" -Root $fixture
        $LASTEXITCODE | Should -Be 0
        foreach ($name in @('Microsoft.PowerShell_profile.ps1', 'Microsoft.VSCode_profile.ps1')) {
            $script:localSharedLoaded = $null
            . "$store/$name"
            $script:localSharedLoaded | Should -Be (Get-Item $store).FullName
        }
        Get-Content "$fixture/documents/Microsoft.VSCode_profile.ps1" | Should -Be '# personal profile'
        # A locked support file must stop deployment before changing host entry points.
        $entryHash = (Get-FileHash "$store/Microsoft.PowerShell_profile.ps1").Hash
        '# changed entry point' | Set-Content "$fixture/powershell-profiles/Microsoft.PowerShell_profile.ps1"
        $lock = [IO.File]::Open("$store/common.ps1", [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        try {
            $output = @(& (Join-Path $PSHOME 'pwsh') -NoProfile -File "$fixture/run.ps1" -Root $fixture 2>&1)
            $LASTEXITCODE | Should -Be 1
            ($output -join "`n") | Should -Match 'Failed to deploy local PowerShell profiles'
        } finally { $lock.Dispose() }
        (Get-FileHash "$store/Microsoft.PowerShell_profile.ps1").Hash | Should -Be $entryHash
        @(Get-Content "$fixture/stopped.txt") | Should -HaveCount 4
    }
}
