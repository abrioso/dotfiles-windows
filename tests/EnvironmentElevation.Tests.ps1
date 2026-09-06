Describe 'Environment variable elevation' {
    BeforeAll {
        $modulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'setup-modules/Set-EnvironmentVariables.ps1'
        $hostPath = (Get-Process -Id $PID).Path
        $harness = Join-Path $TestDrive 'environment-harness.ps1'
        @'
param($ModulePath, $ConfigPath, $ResultPath, [int]$ChildExitCode, [switch]$MachineOnly)
$ErrorActionPreference = 'Stop'
function Test-IsElevated { return $false }
function Start-Process {
    param($FilePath, $ArgumentList, $Verb, [switch]$Wait, [switch]$PassThru, $ErrorAction)
    if ($Verb -ne 'RunAs' -or $ArgumentList -notmatch '-MachineOnly') { throw 'Expected machine-only elevation.' }
    Set-Content -LiteralPath $ResultPath $ArgumentList
    return [pscustomobject]@{ ExitCode = $ChildExitCode }
}
$ast = [System.Management.Automation.Language.Parser]::ParseFile($ModulePath, [ref]$null, [ref]$null)
$body = $ast.EndBlock.Statements | Where-Object { $_ -is [System.Management.Automation.Language.TryStatementAst] } | Select-Object -First 1
. ([scriptblock]::Create($body.Extent.Text))
'@ | Set-Content $harness
    }
    It 'requests machine-only elevation and propagates child failure' {
        $config = Join-Path $TestDrive 'variables.json'
        $result = Join-Path $TestDrive 'elevation.txt'
        @{ EnvironmentVariables = @(@{ Name = 'DOTFILES_TEST_' + [guid]::NewGuid().ToString('N'); Value = 'test'; Scope = 'Machine' }) } | ConvertTo-Json -Depth 4 | Set-Content $config
        & $hostPath -NoProfile -File $harness -ModulePath $modulePath -ConfigPath $config -ResultPath $result -ChildExitCode 7 2>&1 | Out-Null
        $LASTEXITCODE | Should -Be 1
        Test-Path $result | Should -BeTrue
        & $hostPath -NoProfile -File $harness -ModulePath $modulePath -ConfigPath $config -ResultPath $result -ChildExitCode 0 2>&1 | Out-Null
        $LASTEXITCODE | Should -Be 0
    }
    It 'does not apply user entries or request elevation in a machine-only run' {
        $config = Join-Path $TestDrive 'user-only.json'
        $result = Join-Path $TestDrive 'unexpected-elevation.txt'
        Set-Content $config '{"EnvironmentVariables":[{"Name":"DOTFILES_TEST_USER","Value":"test","Scope":"User"}]}'
        & $hostPath -NoProfile -File $harness -ModulePath $modulePath -ConfigPath $config -ResultPath $result -ChildExitCode 0 -MachineOnly 2>&1 | Out-Null
        $LASTEXITCODE | Should -Be 0
        Test-Path $result | Should -BeFalse
    }
    It 'fails invalid configuration before requesting elevation' {
        $config = Join-Path $TestDrive 'invalid.json'
        $result = Join-Path $TestDrive 'invalid-elevation.txt'
        Set-Content $config '{"EnvironmentVariables":[{"Name":"DOTFILES_TEST","Value":"test","Scope":"Invalid"}]}'
        & $hostPath -NoProfile -File $harness -ModulePath $modulePath -ConfigPath $config -ResultPath $result -ChildExitCode 0 2>&1 | Out-Null
        $LASTEXITCODE | Should -Be 1
        Test-Path $result | Should -BeFalse
    }
}
