Describe 'Bootstrap prerequisite scope policy' {
    BeforeAll {
        $repositoryRoot = Split-Path -Parent $PSScriptRoot
        . "$repositoryRoot/setup-scripts/setup-functions.ps1"
        . "$repositoryRoot/setup-scripts/winget-functions.ps1"
        $ast = [Management.Automation.Language.Parser]::ParseFile("$repositoryRoot/setup-modules/Install-WingetPackages.ps1", [ref]$null, [ref]$null)
        $loop = $ast.Find({ param($node) $node -is [Management.Automation.Language.ForEachStatementAst] -and $node.Variable.VariablePath.UserPath -eq 'packageSpec' }, $true)
        $applyLoop = [scriptblock]::Create($loop.Extent.Text)
        # Intercept every install: these tests never invoke the real WinGet executable.
        function winget {
            $arguments = @($args)
            $id = $arguments[[Array]::IndexOf($arguments, '--id') + 1]
            $scope = $arguments[[Array]::IndexOf($arguments, '--scope') + 1]
            $script:prerequisiteCalls.Add([pscustomobject]@{ Id=$id; Scope=$scope; Arguments=$arguments })
            $global:LASTEXITCODE = $script:prerequisiteExitCode
            if ($script:prerequisiteExitCode -eq 0) {
                if ($id -eq 'Git.Git') {
                    $script:gitAvailable = $script:publishGitCommand
                    $script:installedGitScope = $scope
                } else { $script:pwshAvailable = $true }
            }
        }
    }
    BeforeEach {
        $script:prerequisiteCalls = [Collections.Generic.List[object]]::new()
        $script:gitAvailable = $false
        $script:pwshAvailable = $false
        $script:installedGitScope = $null
        $script:prerequisiteExitCode = 0
        $script:publishGitCommand = $true
        $script:testConfigDirectory = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:testConfigDirectory | Out-Null
        Copy-Item -LiteralPath "$repositoryRoot/dotfiles-configurations/winget-packages.json.example" `
            -Destination (Join-Path $script:testConfigDirectory 'winget-packages.json')
        Copy-Item -LiteralPath "$repositoryRoot/dotfiles-configurations/dotfiles-bootstrap-variables.json.example" `
            -Destination (Join-Path $script:testConfigDirectory 'dotfiles-bootstrap-variables.json')
        Mock Get-Command {
            if ($Name -eq 'winget' -or ($Name -eq 'git' -and $script:gitAvailable) -or
                ($Name -eq 'pwsh' -and $script:pwshAvailable)) { [pscustomobject]@{ Name=$Name } }
        } -ParameterFilter { $Name -in @('winget', 'git', 'pwsh') }
        Mock Update-DotfilesProcessPath { }
        Mock Write-Info { }
        Mock Write-ErrorMessage { }
        Mock Start-Process { throw 'Unexpected explicit elevation or package installation' }
        Mock Invoke-DotfilesWingetQuery {
            param($WingetPath, $Arguments)
            $scopeIndex = [Array]::IndexOf($Arguments, '--scope')
            if ($scopeIndex -ge 0 -and $Arguments[$scopeIndex + 1] -ne $script:installedGitScope) {
                [pscustomobject]@{ ExitCode=-1978335212; Output='' }
            } else { [pscustomobject]@{ ExitCode=0; Output='Git Git.Git fixture-version' } }
        }
    }
    It 'installs Git machine-wide and PowerShell per-user and satisfies every catalog declaration' {
        Install-DotfilesPrerequisites -ConfigDirectory $script:testConfigDirectory | Should -BeTrue
        $script:prerequisiteCalls | Should -HaveCount 2
        ($script:prerequisiteCalls | Where-Object Id -EQ 'Git.Git').Scope | Should -Be machine
        ($script:prerequisiteCalls | Where-Object Id -EQ 'Microsoft.PowerShell').Scope | Should -Be user
        $catalog = Get-Content "$repositoryRoot/dotfiles-configurations/winget-packages.json.example" -Raw | ConvertFrom-Json
        foreach ($group in $catalog.PSObject.Properties) {
            foreach ($package in @($group.Value)) {
                if ($package.id -in @('Git.Git', 'Microsoft.PowerShell')) {
                    $request = $script:prerequisiteCalls | Where-Object Id -EQ $package.id
                    $request.Scope | Should -Be $package.scope
                }
            }
        }
        $gitEntry = @($catalog.base | Where-Object id -EQ 'Git.Git')[0]
        $packageSpecs = @([pscustomobject]@{ Id='Git.Git'; Scope=$gitEntry.scope; InstallerType=$null })
        $failedPackages = [Collections.Generic.List[string]]::new()
        $wingetPath = 'winget'
        & $applyLoop
        $failedPackages.Count | Should -Be 0
        $script:prerequisiteCalls | Should -HaveCount 2
        Should -Invoke Start-Process -Times 0 -Exactly
    }
    It 'reuses an existing machine installation without installing or refreshing PATH' {
        $script:gitAvailable = $true
        $script:pwshAvailable = $true
        $script:installedGitScope = 'machine'
        Install-DotfilesPrerequisites -ConfigDirectory $script:testConfigDirectory | Should -BeTrue
        $script:prerequisiteCalls | Should -HaveCount 0
        Should -Invoke Update-DotfilesProcessPath -Times 0 -Exactly
        Should -Invoke Start-Process -Times 0 -Exactly
    }
    It 'preserves an existing user installation and leaves explicit scope reconciliation to package apply' {
        $script:gitAvailable = $true
        $script:pwshAvailable = $true
        $script:installedGitScope = 'user'
        Install-DotfilesPrerequisites -ConfigDirectory $script:testConfigDirectory | Should -BeTrue
        $packageSpecs = @([pscustomobject]@{ Id='Git.Git'; Scope='machine'; InstallerType=$null })
        $failedPackages = [Collections.Generic.List[string]]::new()
        $wingetPath = 'winget'
        & $applyLoop
        $failedPackages.Count | Should -Be 1
        $script:prerequisiteCalls | Should -HaveCount 0
        Should -Invoke Start-Process -Times 0 -Exactly
    }
    It 'stops on Git installer failure or cancellation without retrying at user scope' {
        $script:pwshAvailable = $true
        $script:prerequisiteExitCode = 1602
        Install-DotfilesPrerequisites -ConfigDirectory $script:testConfigDirectory | Should -BeFalse
        $script:prerequisiteCalls | Should -HaveCount 1
        $script:prerequisiteCalls[0].Scope | Should -Be machine
        Should -Invoke Update-DotfilesProcessPath -Times 0 -Exactly
    }
    It 'rejects installer success when Git is still unavailable after PATH refresh' {
        $script:pwshAvailable = $true
        $script:publishGitCommand = $false
        Install-DotfilesPrerequisites -ConfigDirectory $script:testConfigDirectory | Should -BeFalse
        $script:prerequisiteCalls | Should -HaveCount 1
        Should -Invoke Update-DotfilesProcessPath -Times 1 -Exactly
    }
    It 'does not start Git installation after PowerShell installation fails' {
        $script:prerequisiteExitCode = 5
        Install-DotfilesPrerequisites -ConfigDirectory $script:testConfigDirectory | Should -BeFalse
        $script:prerequisiteCalls | Should -HaveCount 1
        $script:prerequisiteCalls[0].Id | Should -Be Microsoft.PowerShell
        $script:prerequisiteCalls[0].Scope | Should -Be user
    }
}
