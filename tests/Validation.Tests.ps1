Describe 'Validation process failure propagation' {
    BeforeAll {
        $runnerSource = Join-Path $PSScriptRoot 'Invoke-Validation.ps1'
        $hostPath = (Get-Process -Id $PID).Path
        $originalModulePath = $env:PSModulePath
        $originalFixtureMode = $env:DOTFILES_VALIDATION_FIXTURE

        function Invoke-ValidationFixture {
            param([string]$Mode)
            $env:DOTFILES_VALIDATION_FIXTURE = $Mode
            $env:PSModulePath = $fixtureModules + [IO.Path]::PathSeparator + $originalModulePath
            $output = & $hostPath -NoProfile -File $fixtureRunner 2>&1
            [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($output -join "`n") }
        }
    }
    BeforeEach {
        $fixtureRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $fixtureModules = Join-Path $fixtureRoot 'modules'
        $fixtureTests = Join-Path $fixtureRoot 'tests'
        New-Item -ItemType Directory -Path $fixtureTests -Force | Out-Null
        $fixtureRunner = Join-Path $fixtureTests 'Invoke-Validation.ps1'
        Copy-Item -LiteralPath $runnerSource -Destination $fixtureRunner
        foreach ($spec in @(@('Pester', '5.7.1'), @('PSScriptAnalyzer', '1.25.0'))) {
            $moduleDirectory = Join-Path $fixtureModules "$($spec[0])/$($spec[1])"
            New-Item -ItemType Directory -Path $moduleDirectory -Force | Out-Null
            New-ModuleManifest -Path "$moduleDirectory/$($spec[0]).psd1" -RootModule "$($spec[0]).psm1" -ModuleVersion $spec[1]
        }
        @'
function Invoke-Pester {
    param([string]$Path, [switch]$PassThru)
    [pscustomobject]@{
        FailedCount = [int]($env:DOTFILES_VALIDATION_FIXTURE -eq 'FailedTest')
        FailedContainersCount = [int]($env:DOTFILES_VALIDATION_FIXTURE -eq 'FailedContainer')
        TotalCount = [int]($env:DOTFILES_VALIDATION_FIXTURE -ne 'EmptySuite')
        PassedCount = 1
        SkippedCount = 0
    }
}
Export-ModuleMember -Function Invoke-Pester
'@ | Set-Content "$fixtureModules/Pester/5.7.1/Pester.psm1"
        @'
function Invoke-ScriptAnalyzer {
    param([string]$Path, [string[]]$Severity)
    if ($env:DOTFILES_VALIDATION_FIXTURE -in @('AnalyzerWarning', 'AnalyzerError')) {
        [pscustomobject]@{
            RuleName = 'FixtureRule'
            Severity = if ($env:DOTFILES_VALIDATION_FIXTURE -eq 'AnalyzerError') { 'Error' } else { 'Warning' }
            ScriptName = 'fixture.ps1'
            Line = 1
            Message = 'Visible fixture diagnostic'
        }
    }
}
Export-ModuleMember -Function Invoke-ScriptAnalyzer
'@ | Set-Content "$fixtureModules/PSScriptAnalyzer/1.25.0/PSScriptAnalyzer.psm1"
        git -C $fixtureRoot init --quiet
        if ($LASTEXITCODE -ne 0) { throw 'Unable to initialize the validation fixture repository.' }
    }
    AfterEach {
        $env:PSModulePath = $originalModulePath
        $env:DOTFILES_VALIDATION_FIXTURE = $originalFixtureMode
    }
    It 'returns a non-zero status for failed tests' {
        $result = Invoke-ValidationFixture -Mode FailedTest
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match '1 failed tests'
    }
    It 'returns a non-zero status for discovery or container errors' {
        $result = Invoke-ValidationFixture -Mode FailedContainer
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match '1 failed containers'
    }
    It 'rejects an empty test suite' {
        $result = Invoke-ValidationFixture -Mode EmptySuite
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match '0 total tests'
    }
    It 'prints analyzer warnings without treating them as errors' {
        $result = Invoke-ValidationFixture -Mode AnalyzerWarning
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'Visible fixture diagnostic'
        $result.Output | Should -Match '0 errors, 1 warnings'
    }
    It 'fails on analyzer errors' {
        $result = Invoke-ValidationFixture -Mode AnalyzerError
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'PSScriptAnalyzer reported errors'
    }
    It 'validates new JSON templates but excludes ignored private JSON' {
        'private.json' | Set-Content (Join-Path $fixtureRoot '.gitignore')
        '{invalid' | Set-Content (Join-Path $fixtureRoot 'private.json')
        (Invoke-ValidationFixture -Mode Success).ExitCode | Should -Be 0
        '{invalid' | Set-Content (Join-Path $fixtureRoot 'new.json.example')
        $result = Invoke-ValidationFixture -Mode Success
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'Invalid JSON in new.json.example'
    }
}
