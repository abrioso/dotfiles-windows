Describe 'Independent verified theme deployment' {
    BeforeAll {
        $repositoryRoot = Split-Path -Parent $PSScriptRoot
        . "$repositoryRoot/setup-scripts/deployment-functions.ps1"
    }
    BeforeEach {
        $fixture = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $sourceDirectory = Join-Path $fixture 'checkout'
        $targetDirectory = Join-Path $fixture 'André [local]/themes'
        New-Item -ItemType Directory $sourceDirectory, $targetDirectory -Force | Out-Null
        $source = Join-Path $sourceDirectory 'theme.json'
        $target = Join-Path $targetDirectory 'theme.json'
        '{"version":1}' | Set-Content -LiteralPath $source
    }
    It 'creates a literal-path copy, then skips it without new backups or writes' {
        (Copy-DotfilesVerifiedFile $source $target).Status | Should -Be Created
        (Get-FileHash -LiteralPath $target).Hash | Should -Be (Get-FileHash -LiteralPath $source).Hash
        $before = (Get-Item -LiteralPath $target).LastWriteTimeUtc
        (Copy-DotfilesVerifiedFile $source $target).Status | Should -Be Unchanged
        (Get-Item -LiteralPath $target).LastWriteTimeUtc | Should -Be $before
        @(Get-ChildItem -LiteralPath $targetDirectory -Force) | Should -HaveCount 1
        '{"local":true}' | Set-Content -LiteralPath $target
        Get-Content -LiteralPath $source | Should -Be '{"version":1}'
    }
    It 'detaches an identical legacy hardlink and keeps the backup independent' {
        New-Item -ItemType HardLink -Path $target -Value $source | Out-Null
        $result = Copy-DotfilesVerifiedFile $source $target
        $result.Status | Should -Be Replaced
        (Get-Item -LiteralPath $target).LinkType | Should -BeNullOrEmpty
        (Get-Item -LiteralPath $result.BackupPath).LinkType | Should -BeNullOrEmpty
        '{"version":2}' | Set-Content -LiteralPath $source
        Get-Content -LiteralPath $target | Should -Be '{"version":1}'
        Get-Content -LiteralPath $result.BackupPath | Should -Be '{"version":1}'
        '{"local":true}' | Set-Content -LiteralPath $target
        Get-Content -LiteralPath $source | Should -Be '{"version":2}'
    }
    It 'keeps unique backups across updates and preserves older .bak files' {
        'custom' | Set-Content -LiteralPath $target
        'older backup' | Set-Content -LiteralPath "$target.bak"
        $first = Copy-DotfilesVerifiedFile $source $target
        'second custom' | Set-Content -LiteralPath $target
        $second = Copy-DotfilesVerifiedFile $source $target
        $first.BackupPath | Should -Not -Be $second.BackupPath
        Get-Content -LiteralPath $first.BackupPath | Should -Be custom
        Get-Content -LiteralPath $second.BackupPath | Should -Be 'second custom'
        Get-Content -LiteralPath "$target.bak" | Should -Be 'older backup'
    }
    It 'replaces a legacy file symlink without changing its referent' {
        try { New-Item -ItemType SymbolicLink -Path $target -Target $source -ErrorAction Stop | Out-Null }
        catch {
            Set-ItResult -Skipped -Because 'This host cannot create a symbolic-link fixture (requires Developer Mode or administrator privileges).'
            return
        }
        $result = Copy-DotfilesVerifiedFile $source $target
        $result.Status | Should -Be Replaced
        (Get-Item -LiteralPath $target).LinkType | Should -BeNullOrEmpty
        '{"local":true}' | Set-Content -LiteralPath $target
        Get-Content -LiteralPath $source | Should -Be '{"version":1}'
        Get-Content -LiteralPath $result.BackupPath | Should -Be '{"version":1}'
    }
    It 'preserves destination and source when staging fails' {
        'custom' | Set-Content -LiteralPath $target
        Mock Copy-Item { throw 'copy failure' }
        { Copy-DotfilesVerifiedFile $source $target } | Should -Throw '*copy failure*'
        Get-Content -LiteralPath $target | Should -Be custom
        Get-Content -LiteralPath $source | Should -Be '{"version":1}'
        @(Get-ChildItem -LiteralPath $targetDirectory -Force) | Should -HaveCount 1
    }
    It 'does not publish a corrupt copy or a changing source (<ChangeSource>)' -ForEach @(
        @{ ChangeSource = $false }, @{ ChangeSource = $true }
    ) {
        'custom' | Set-Content -LiteralPath $target
        Mock Copy-Item {
            if ($ChangeSource) {
                [IO.File]::Copy($LiteralPath, $Destination)
                'changed source' | Set-Content -LiteralPath $LiteralPath
            } else { 'corrupt copy' | Set-Content -LiteralPath $Destination }
        }
        { Copy-DotfilesVerifiedFile $source $target } | Should -Throw '*verification failed*'
        Get-Content -LiteralPath $target | Should -Be custom
        @(Get-ChildItem -LiteralPath $targetDirectory -Force) | Should -HaveCount 1
    }
    It 'does not replace a changed destination observed during staging' {
        'custom' | Set-Content -LiteralPath $target
        Mock Copy-Item {
            [IO.File]::Copy($LiteralPath, $Destination)
            'concurrent edit' | Set-Content -LiteralPath $target
        }
        { Copy-DotfilesVerifiedFile $source $target } | Should -Throw '*destination changed*'
        Get-Content -LiteralPath $target | Should -Be 'concurrent edit'
        @(Get-ChildItem -LiteralPath $targetDirectory -Force) | Should -HaveCount 1
    }
    It 'retains the original when backup verification fails' {
        'custom' | Set-Content -LiteralPath $target
        Mock Get-FileHash { [pscustomobject]@{ Hash = 'incorrect' } } -ParameterFilter { $LiteralPath -like '*.bak' }
        { Copy-DotfilesVerifiedFile $source $target } | Should -Throw '*backup verification failed*'
        Get-Content -LiteralPath $target | Should -Be custom
        @(Get-ChildItem -LiteralPath $targetDirectory -Filter '*.tmp' -Force) | Should -HaveCount 0
    }
    It 'retains a locked destination and its backup if publication fails' {
        'custom' | Set-Content -LiteralPath $target
        $handle = [IO.File]::Open($target, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        try { { Copy-DotfilesVerifiedFile $source $target } | Should -Throw }
        finally { $handle.Dispose() }
        Get-Content -LiteralPath $target | Should -Be custom
        @(Get-ChildItem -LiteralPath $targetDirectory -Filter '*.bak') | Should -HaveCount 1
        @(Get-ChildItem -LiteralPath $targetDirectory -Filter '*.tmp' -Force) | Should -HaveCount 0
    }
    It 'rejects an identical path and a directory destination without mutation' {
        { Copy-DotfilesVerifiedFile $source $source } | Should -Throw '*different paths*'
        { Copy-DotfilesVerifiedFile $source $targetDirectory } | Should -Throw '*destination is a directory*'
        Get-Content -LiteralPath $source | Should -Be '{"version":1}'
    }
    It 'rejects directory junctions that would redirect deployment into the checkout' {
        $junction = Join-Path $fixture 'redirected'
        New-Item -ItemType Junction -Path $junction -Target $sourceDirectory | Out-Null
        { Copy-DotfilesVerifiedFile $source (Join-Path $junction 'theme.json') } | Should -Throw '*link or junction*'
        Get-Content -LiteralPath $source | Should -Be '{"version":1}'
        @(Get-ChildItem -LiteralPath $sourceDirectory -Force) | Should -HaveCount 1
    }
}

Describe 'Theme module integration' {
    BeforeAll { $repositoryRoot = Split-Path -Parent $PSScriptRoot }
    It 'deploys twice without touching the checkout and finalizes logging on failure' {
        $fixture = Join-Path $TestDrive 'module'
        New-Item -ItemType Directory "$fixture/setup-scripts", "$fixture/setup-modules", "$fixture/poshthemes", "$fixture/user" -Force | Out-Null
        Copy-Item "$repositoryRoot/setup-scripts/deployment-functions.ps1" "$fixture/setup-scripts/deployment-functions.ps1"
        Copy-Item "$repositoryRoot/setup-modules/Install-OmpConfig.ps1" "$fixture/setup-modules/Install-OmpConfig.ps1"
        '{"version":1}' | Set-Content "$fixture/poshthemes/theme.json"
        @'
function Start-Logging { param($LogFilePath) }
function Stop-Logging { Add-Content (Join-Path $dotfileRootDir 'stopped.txt') 'stopped' }
function Write-Info { param($Message) }
function Write-ErrorMessage { param($Message) Write-Output $Message }
function Write-WarningMessage { param($Message) Write-Output $Message }
'@ | Set-Content "$fixture/setup-scripts/setup-functions.ps1"
        @'
param([string]$Root)
$env:USERPROFILE = Join-Path $Root 'user'
$global:LASTEXITCODE = 0
& (Join-Path $Root 'setup-modules/Install-OmpConfig.ps1')
exit $LASTEXITCODE
'@ | Set-Content "$fixture/run.ps1"
        foreach ($run in 1..2) {
            & (Join-Path $PSHOME 'pwsh') -NoProfile -File "$fixture/run.ps1" -Root $fixture
            $LASTEXITCODE | Should -Be 0
        }
        $target = "$fixture/user/.config/oh-my-posh/poshthemes/theme.json"
        '{"local":true}' | Set-Content $target
        Get-Content "$fixture/poshthemes/theme.json" | Should -Be '{"version":1}'
        # A missing source directory reaches the module's own failure/finalizer path.
        Rename-Item "$fixture/poshthemes" 'unavailable'
        $output = @(& (Join-Path $PSHOME 'pwsh') -NoProfile -File "$fixture/run.ps1" -Root $fixture 2>&1)
        $LASTEXITCODE | Should -Be 1
        ($output -join "`n") | Should -Match 'Failed to deploy'
        @(Get-Content "$fixture/stopped.txt") | Should -HaveCount 3
        Get-Content $target | Should -Be '{"local":true}'
    }
}
