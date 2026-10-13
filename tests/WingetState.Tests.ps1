Describe 'WinGet package state' {
    BeforeAll { . "$PSScriptRoot/../setup-scripts/winget-functions.ps1" }
    It 'filters exact IDs by the configured scope and ignores localized display labels' {
        $result = Get-DotfilesWingetPackageState -Id Vendor.App -Scope machine -Query {
            param($Arguments)
            ($Arguments -join ' ') | Should -Be 'list --id Vendor.App --exact --source winget --disable-interactivity --scope machine'
            [pscustomobject]@{ ExitCode = 0; Output = 'Nome  Vendor.App  versão desconhecida' }
        }
        $result.Presence | Should -Be Present
        $result.Status | Should -Be Passed
    }
    It 'recognizes only the no-applications HRESULT as absence (<Code>)' -ForEach @(
        @{ Code = -1978335212 }, @{ Code = 2316632084 }
    ) {
        $result = Get-DotfilesWingetPackageState -Id Vendor.App -Scope user -Query { [pscustomobject]@{ ExitCode = $Code; Output = 'localized message' } }
        $result.Presence | Should -Be Missing
        $result.Status | Should -Be Drift
    }
    It 'reports unknown rather than absence for <Code>' -ForEach @(
        @{ Code = 1 }, @{ Code = -1978335211 }, @{ Code = 0 }, @{ Code = $null }
    ) {
        $result = Get-DotfilesWingetPackageState -Id Vendor.App -Query { [pscustomobject]@{ ExitCode = $Code; Output = 'Vendor.App.Extension private-secret' } }
        $result.Presence | Should -Be Unknown
        $result.Message | Should -Not -Match 'private-secret'
    }
    It 'distinguishes wrong scope from source failures on the fallback query' {
        $result = Get-DotfilesWingetPackageState -Id Vendor.App -Scope machine -Query {
            param($Arguments)
            if ($Arguments -contains '--scope') { [pscustomobject]@{ ExitCode = -1978335212; Output = '' } }
            else { [pscustomobject]@{ ExitCode = 0; Output = 'Vendor.App' } }
        }
        $result.Presence | Should -Be ScopeMismatch
        $result.Status | Should -Be Drift
        $result = Get-DotfilesWingetPackageState -Id Vendor.App -Scope machine -Query {
            param($Arguments)
            [pscustomobject]@{ ExitCode = $(if ($Arguments -contains '--scope') { -1978335212 } else { 1 }); Output = '' }
        }
        $result.Presence | Should -Be Unknown
    }
    It 'does not expose query exceptions or certify installer type from presence' {
        (Get-DotfilesWingetPackageState -Id Vendor.App -Query { throw 'private-secret' }).Message | Should -Not -Match 'private-secret'
        $result = Get-DotfilesWingetPackageState -Id Vendor.App -InstallerType wix -Query { [pscustomobject]@{ ExitCode = 0; Output = 'Vendor.App' } }
        $result.Presence | Should -Be Present
        $result.Status | Should -Be Unknown
    }
}

Describe 'WinGet apply state transitions' {
    BeforeAll {
        $repositoryRoot = Split-Path -Parent $PSScriptRoot
        . "$repositoryRoot/setup-scripts/winget-functions.ps1"
        $ast = [Management.Automation.Language.Parser]::ParseFile("$repositoryRoot/setup-modules/Install-WingetPackages.ps1", [ref]$null, [ref]$null)
        $loop = $ast.Find({ param($node) $node -is [Management.Automation.Language.ForEachStatementAst] -and $node.Variable.VariablePath.UserPath -eq 'packageSpec' }, $true)
        $applyLoop = [scriptblock]::Create($loop.Extent.Text)
        function Invoke-WingetTestExecutable { $global:LASTEXITCODE = 0 }
    }
    BeforeEach {
        $wingetPath = 'Invoke-WingetTestExecutable'
        $packageSpecs = @([pscustomobject]@{ Id = 'Vendor.App'; Scope = 'user'; InstallerType = $null })
        $failedPackages = [Collections.Generic.List[string]]::new()
        Mock Invoke-WingetTestExecutable { $global:LASTEXITCODE = 0 }
        Mock Start-Process { throw 'Elevation must not run' }
    }
    It 'does not install an existing matching package' {
        Mock Invoke-DotfilesWingetQuery { [pscustomobject]@{ ExitCode = 0; Output = 'Vendor.App' } }
        & $applyLoop
        $failedPackages.Count | Should -Be 0
        Should -Invoke Invoke-WingetTestExecutable -Times 0 -Exactly
        Should -Invoke Start-Process -Times 0 -Exactly
    }
    It 'does not mutate when queries fail or the package is in the wrong scope' -ForEach @(
        @{ WrongScope = $false }, @{ WrongScope = $true }
    ) {
        $packageSpecs[0].Scope = 'machine'
        Mock Invoke-DotfilesWingetQuery {
            param($Arguments)
            $code = if (-not $WrongScope) { 1 } elseif ($Arguments -contains '--scope') { -1978335212 } else { 0 }
            [pscustomobject]@{ ExitCode = $code; Output = 'Vendor.App' }
        }
        & $applyLoop
        $failedPackages.Count | Should -Be 1
        Should -Invoke Invoke-WingetTestExecutable -Times 0 -Exactly
        Should -Invoke Start-Process -Times 0 -Exactly
    }
    It 'rejects installer success when the post-install state is <State>' -ForEach @(
        @{ State = 'Missing' }, @{ State = 'Unknown' }, @{ State = 'ScopeMismatch' }
    ) {
        $script:wingetTestQueryCount = 0
        Mock Get-DotfilesWingetPackageState {
            $script:wingetTestQueryCount++
            [pscustomobject]@{ Presence = $(if ($script:wingetTestQueryCount -eq 1) { 'Missing' } else { $State }); Status = 'Drift'; Message = 'fixture state' }
        }
        & $applyLoop
        $failedPackages.Count | Should -Be 1
        Should -Invoke Invoke-WingetTestExecutable -Times 1 -Exactly
    }
    It 'verifies a missing <Scope> package after installation and preserves constraints' -ForEach @(
        @{ Scope = 'user' }, @{ Scope = 'machine' }
    ) {
        $packageSpecs[0].Scope = $Scope
        $packageSpecs[0].InstallerType = 'wix'
        $script:wingetTestQueryCount = 0
        Mock Invoke-DotfilesWingetQuery {
            $script:wingetTestQueryCount++
            [pscustomobject]@{ ExitCode = $(if ($script:wingetTestQueryCount -le 2) { -1978335212 } else { 0 }); Output = 'Vendor.App' }
        }
        Mock Start-Process { [pscustomobject]@{ ExitCode = 0 } }
        & $applyLoop
        $failedPackages.Count | Should -Be 0
        if ($Scope -eq 'machine') {
            Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {
                $Verb -eq 'RunAs' -and $ArgumentList -contains '--scope' -and $ArgumentList -contains 'machine' -and $ArgumentList -contains '--installer-type' -and $ArgumentList -contains 'wix'
            }
            Should -Invoke Invoke-WingetTestExecutable -Times 0 -Exactly
        } else {
            Should -Invoke Start-Process -Times 0 -Exactly
            Should -Invoke Invoke-WingetTestExecutable -Times 1 -Exactly
        }
        Should -Invoke Invoke-DotfilesWingetQuery -Times 3 -Exactly
    }
    It 'records a native installer failure without claiming verified success' {
        Mock Get-DotfilesWingetPackageState { [pscustomobject]@{ Presence = 'Missing'; Status = 'Drift'; Message = 'missing' } }
        Mock Invoke-WingetTestExecutable { $global:LASTEXITCODE = 9 }
        & $applyLoop
        $failedPackages.Count | Should -Be 1
        Should -Invoke Get-DotfilesWingetPackageState -Times 1 -Exactly
    }
}
