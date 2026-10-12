Describe 'Local apply checkout selection' {
    BeforeAll {
        $repositoryRoot = Split-Path -Parent $PSScriptRoot
        . "$repositoryRoot/setup-scripts/setup-functions.ps1"
        $script:applyTestGitExecutable = (Get-Command git -CommandType Application | Select-Object -First 1).Source
        function Invoke-ApplyTestGit {
            param([string]$Root, [string[]]$Arguments)
            $output = @(& $script:applyTestGitExecutable -C $Root @Arguments 2>&1)
            if ($LASTEXITCODE -ne 0) { throw "Fixture Git command failed: $($Arguments -join ' ')" }
            $output
        }
        function New-ApplyTestRepository {
            param([string]$Path)
            New-Item -ItemType Directory $Path -Force | Out-Null
            Invoke-ApplyTestGit $Path @('init', '-b', 'develop') | Out-Null
            Invoke-ApplyTestGit $Path @('config', 'user.name', 'Fixture') | Out-Null
            Invoke-ApplyTestGit $Path @('config', 'user.email', 'fixture@example.invalid') | Out-Null
            'initial' | Set-Content "$Path/file.txt"
            Invoke-ApplyTestGit $Path @('add', 'file.txt') | Out-Null
            Invoke-ApplyTestGit $Path @('commit', '-m', 'fixture') | Out-Null
        }
    }
    BeforeEach {
        $fixture = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $source = Join-Path $fixture 'source'
        $target = Join-Path $fixture 'workspace/clone'
        $script:applyTestGitCalls = [Collections.Generic.List[string]]::new()
        Mock git {
            $script:applyTestGitCalls.Add($args -join ' ')
            if ($args -contains 'fetch' -or $args -contains 'pull' -or $args -contains 'checkout' -or $args -contains 'switch') { throw 'Forbidden repository mutation during apply' }
            $output = @(& $script:applyTestGitExecutable @args 2>&1)
            $global:LASTEXITCODE = $LASTEXITCODE
            $output
        }
    }
    It 'uses the invoked dirty checkout without contacting its removed remote or configured workspace' {
        New-ApplyTestRepository $source
        Invoke-ApplyTestGit $source @('remote', 'add', 'origin', "$fixture/missing-remote") | Out-Null
        'local changes' | Set-Content "$source/file.txt"
        'untracked' | Set-Content "$source/untracked.txt"
        $beforeHead = Invoke-ApplyTestGit $source @('rev-parse', 'HEAD')
        $beforeStatus = (Invoke-ApplyTestGit $source @('status', '--porcelain')) -join "`n"
        $result = Get-DotfilesApplyCheckout -SourceRoot $source -TargetRoot $target -RepositoryUrl "$fixture/missing-remote" -Branch main
        $result.Root | Should -Be $source
        $result.WasCloned | Should -BeFalse
        $result.Commit | Should -Be $beforeHead
        ((Invoke-ApplyTestGit $source @('status', '--porcelain')) -join "`n") | Should -Be $beforeStatus
        Test-Path $target | Should -BeFalse
        $script:applyTestGitCalls | Should -HaveCount 2
    }
    It 'supports a Git worktree with a .git file and does not switch it to the configured branch' {
        $base = Join-Path $fixture 'base'
        New-ApplyTestRepository $base
        Invoke-ApplyTestGit $base @('worktree', 'add', '-b', 'feature/local', $source) | Out-Null
        (Get-Item "$source/.git" -Force -ErrorAction Stop).PSIsContainer | Should -BeFalse
        $result = Get-DotfilesApplyCheckout -SourceRoot $source -TargetRoot $target -RepositoryUrl 'unused' -Branch main
        $result.Root | Should -Be $source
        (Invoke-ApplyTestGit $source @('branch', '--show-current')) | Should -Be 'feature/local'
    }
    It 'allows an invoked detached checkout unless a specific branch was explicitly requested' {
        New-ApplyTestRepository $source
        Invoke-ApplyTestGit $source @('checkout', '--detach') | Out-Null
        (Get-DotfilesApplyCheckout -SourceRoot $source -TargetRoot $target -RepositoryUrl unused -Branch main).Root | Should -Be $source
        $LASTEXITCODE | Should -Be 0
        { Get-DotfilesApplyCheckout -SourceRoot $source -TargetRoot $target -RepositoryUrl unused -Branch main -RequireBranch } | Should -Throw '*does not switch branches*'
    }
    It 'clones the selected branch once from a Git-free source, then reuses the same local HEAD' {
        $remote = Join-Path $fixture 'remote'
        New-ApplyTestRepository $remote
        New-Item -ItemType Directory $source | Out-Null
        $first = Get-DotfilesApplyCheckout -SourceRoot $source -TargetRoot $target -RepositoryUrl $remote -Branch develop
        $first.WasCloned | Should -BeTrue
        (Invoke-ApplyTestGit $target @('branch', '--show-current')) | Should -Be develop
        'remote update' | Set-Content "$remote/file.txt"
        Invoke-ApplyTestGit $remote @('commit', '-am', 'remote update') | Out-Null
        $second = Get-DotfilesApplyCheckout -SourceRoot $source -TargetRoot $target -RepositoryUrl $remote -Branch develop
        $second.WasCloned | Should -BeFalse
        $second.Commit | Should -Be $first.Commit
        @($script:applyTestGitCalls | Where-Object { $_ -like 'clone *' }) | Should -HaveCount 1
    }
    It 'rejects a different existing transport target branch before synchronizing or applying anything' {
        New-ApplyTestRepository $target
        New-Item -ItemType Directory $source | Out-Null
        { Get-DotfilesApplyCheckout -SourceRoot $source -TargetRoot $target -RepositoryUrl unused -Branch main } | Should -Throw '*update.ps1*'
        (Invoke-ApplyTestGit $target @('branch', '--show-current')) | Should -Be develop
    }
    It 'rejects an existing non-repository target without overwriting its files' {
        New-Item -ItemType Directory $source, $target -Force | Out-Null
        'preserve' | Set-Content "$target/existing.txt"
        { Get-DotfilesApplyCheckout -SourceRoot $source -TargetRoot $target -RepositoryUrl unused -Branch main } | Should -Throw '*will not overwrite*'
        Get-Content "$target/existing.txt" | Should -Be preserve
        $script:applyTestGitCalls | Should -HaveCount 0
    }
    It 'reports a failed initial clone without applying or deleting the partial destination' {
        New-Item -ItemType Directory $source -Force | Out-Null
        Mock git {
            New-Item -ItemType Directory $target -Force | Out-Null
            'partial clone' | Set-Content "$target/partial.txt"
            $global:LASTEXITCODE = 128
            'fixture clone failure'
        }
        { Get-DotfilesApplyCheckout -SourceRoot $source -TargetRoot $target -RepositoryUrl unused -Branch develop } | Should -Throw '*Initial clone failed*'
        Get-Content "$target/partial.txt" | Should -Be 'partial clone'
    }
    It 'applies setup with exit <ModuleCode> from archive <FromArchive> without updating an existing checkout' -ForEach @(
        @{ModuleCode=0;FromArchive=$false}, @{ModuleCode=3010;FromArchive=$false}, @{ModuleCode=0;FromArchive=$true}
    ) {
        if ($FromArchive) { New-Item -ItemType Directory $source -Force | Out-Null }
        else { New-ApplyTestRepository $source }
        Copy-Item "$repositoryRoot/setup-scripts" $source -Recurse
        Copy-Item "$repositoryRoot/setup-modules" $source -Recurse
        $configuration = Join-Path $source 'dotfiles-configurations'
        New-Item -ItemType Directory $configuration | Out-Null
        foreach ($file in Get-ChildItem "$repositoryRoot/dotfiles-configurations/*.json.example") {
            Copy-Item $file.FullName (Join-Path $configuration ($file.Name -replace '\.example$', ''))
        }
        $bootstrapPath = Join-Path $configuration 'dotfiles-bootstrap-variables.json'
        $bootstrap = Get-Content $bootstrapPath -Raw | ConvertFrom-Json
        foreach ($name in @('INSTALL_FEATURES', 'INSTALL_CAPABILITIES', 'INSTALL_PACKAGES')) { $bootstrap.$name = @() }
        $bootstrap.INSTALL_SETTINGS = @('fixture')
        $bootstrap.WORKSPACE_FOLDER = if ($FromArchive) { 'workspace' } else { 'unused-workspace' }
        $bootstrap.GITHUB_DOTFILES_REPO = 'clone'
        $bootstrap.GITHUB_DOTFILES_BRANCH = 'saved-preference'
        $bootstrap | ConvertTo-Json -Depth 20 | Set-Content $bootstrapPath
        '{"settings":{"fixture":[{"script":"Fixture.ps1"}]}}' | Set-Content "$configuration/setup-modules.json"
        "exit $ModuleCode" | Set-Content "$source/setup-modules/Fixture.ps1"
        @'
function Initialize-DotfilesConfiguration { }
function Install-DotfilesPrerequisites { $true }
function Update-DotfilesProcessPath { }
function Start-Logging { param($LogFilePath, [switch]$PassThru, [switch]$Append); $LogFilePath }
function Stop-Logging { }
function Complete-DotfilesSetupLogging { param($LogFilePath, $DotfilesDirectory); $LogFilePath }
$env:USERPROFILE = Split-Path -Parent $dotfileRootDir
'@ | Add-Content "$source/setup-scripts/setup-functions.ps1"
        if (-not $FromArchive) {
            "function Set-DotfilesBootstrapBranch { throw 'FORBIDDEN saved branch write' }" | Add-Content "$source/setup-scripts/setup-functions.ps1"
        }
        $remote = Join-Path $fixture 'remote'
        $allowClone = if ($FromArchive) { '$true' } else { '$false' }
        @"
function git {
    if (`$args[0] -eq 'clone') {
        if (-not $allowClone) { throw 'FORBIDDEN clone of an existing checkout' }
    } elseif (`$args[0] -ne '-C' -or `$args[2] -notin @('rev-parse', 'symbolic-ref')) { throw 'FORBIDDEN Git mutation or network' }
    & '$($script:applyTestGitExecutable.Replace("'", "''"))' @args
    `$global:LASTEXITCODE = `$LASTEXITCODE
}
function Resolve-DotfilesRepositoryUrl { '$($remote.Replace("'", "''"))' }
"@ | Add-Content "$source/setup-scripts/setup-functions.ps1"
        if ($FromArchive) {
            New-ApplyTestRepository $remote
            Copy-Item "$source/setup-scripts" $remote -Recurse
            Copy-Item "$source/setup-modules" $remote -Recurse
            Invoke-ApplyTestGit $remote @('add', '.') | Out-Null
            Invoke-ApplyTestGit $remote @('commit', '-m', 'fixture setup') | Out-Null
        }
        $beforeBootstrap = (Get-FileHash $bootstrapPath).Hash
        $beforeHead = Invoke-ApplyTestGit $(if ($FromArchive) { $remote } else { $source }) @('rev-parse', 'HEAD')
        if (-not $FromArchive) { $beforeStatus = (Invoke-ApplyTestGit $source @('status', '--porcelain')) -join "`n" }
        $output = & (Join-Path $PSHOME 'pwsh.exe') -NoProfile -File "$source/setup-scripts/setup.ps1" -NonInteractive -BootstrapBranch develop 2>&1
        $LASTEXITCODE | Should -Be $ModuleCode
        ($output -join "`n") | Should -Not -Match 'FORBIDDEN'
        (Get-FileHash $bootstrapPath).Hash | Should -Be $beforeBootstrap
        $appliedRoot = if ($FromArchive) { $target } else { $source }
        (Invoke-ApplyTestGit $appliedRoot @('rev-parse', 'HEAD')) | Should -Be $beforeHead
        if (-not $FromArchive) {
            ((Invoke-ApplyTestGit $source @('status', '--porcelain')) -join "`n") | Should -Be $beforeStatus
            Test-Path "$fixture/unused-workspace" | Should -BeFalse
        } else {
            $savedPath = "$target/dotfiles-configurations/dotfiles-bootstrap-variables.json"
            (Get-Content $savedPath -Raw | ConvertFrom-Json).GITHUB_DOTFILES_BRANCH | Should -Be develop
            $savedHash = (Get-FileHash $savedPath).Hash
            'remote advance' | Set-Content "$remote/file.txt"
            Invoke-ApplyTestGit $remote @('commit', '-am', 'remote advance') | Out-Null
            $repeat = & (Join-Path $PSHOME 'pwsh.exe') -NoProfile -File "$source/setup-scripts/setup.ps1" -NonInteractive -BootstrapBranch develop 2>&1
            $LASTEXITCODE | Should -Be 0
            ($repeat -join "`n") | Should -Not -Match 'FORBIDDEN'
            (Invoke-ApplyTestGit $target @('rev-parse', 'HEAD')) | Should -Be $beforeHead
            (Get-FileHash $savedPath).Hash | Should -Be $savedHash
            (Get-FileHash $bootstrapPath).Hash | Should -Be $beforeBootstrap
        }
    }
}
