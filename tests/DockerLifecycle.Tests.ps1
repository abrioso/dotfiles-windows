Describe 'Standalone Docker lifecycle' {
    BeforeAll {
        $root = Split-Path -Parent $PSScriptRoot
        $hostPath = (Get-Process -Id $PID).Path
        $harness = Join-Path $TestDrive 'docker-harness.ps1'
        @'
param($ScriptPath, $ParametersPath, $CallsPath, [int]$DockerExitCode)
function docker {
    ConvertTo-Json -InputObject @($args) -Compress | Add-Content -LiteralPath $CallsPath
    $global:LASTEXITCODE = $DockerExitCode
}
$parameters = Get-Content -LiteralPath $ParametersPath -Raw | ConvertFrom-Json -AsHashtable
& $ScriptPath @parameters
if ($null -ne $LASTEXITCODE) { exit $LASTEXITCODE }
'@ | Set-Content $harness
        function Invoke-DockerFixture {
            param([string]$Script, [hashtable]$Parameters, [int]$Failure = 0)
            $parametersPath = Join-Path $TestDrive 'parameters.json'
            $Parameters | ConvertTo-Json | Set-Content $parametersPath
            $output = & $hostPath -NoProfile -File $harness -ScriptPath "$root/powershell-scripts/$Script" `
                -ParametersPath $parametersPath -CallsPath $callsPath -DockerExitCode $Failure 2>&1
            [pscustomobject]@{ExitCode=$LASTEXITCODE;Output=($output -join "`n")}
        }
    }
    BeforeEach {
        $fixtureDirectory = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $fixtureDirectory
        $composePath = Join-Path $fixtureDirectory 'compose.yml'
        "# dotfiles-managed ollama compose v1`nservices: {}`n" | Set-Content $composePath
        $callsPath = Join-Path $fixtureDirectory 'calls.jsonl'
    }
    It 'stops the explicit project without removing volumes' {
        $result = Invoke-DockerFixture '13.docker.ollama.user.stop.ps1' @{ComposePath=$composePath;ProjectName='fixture'}
        $result.ExitCode | Should -Be 0
        $calls = @(Get-Content $callsPath)
        $calls | Should -HaveCount 1
        $arguments = $calls[0] | ConvertFrom-Json
        $arguments[-1] | Should -Be stop
        $arguments | Should -Contain $composePath
        $arguments | Should -Contain fixture
        $arguments | Should -Not -Contain '--volumes'
    }
    It 'removes containers without deleting volumes for Down' {
        (Invoke-DockerFixture '13.docker.ollama.user.stop.ps1' @{ComposePath=$composePath;Action='Down'}).ExitCode | Should -Be 0
        $arguments = Get-Content $callsPath | ConvertFrom-Json
        $arguments[-1] | Should -Be down
        $arguments | Should -Not -Contain '--volumes'
    }
    It 'does not invoke Docker for a purge preview' {
        (Invoke-DockerFixture '13.docker.ollama.user.stop.ps1' @{ComposePath=$composePath;Action='Purge';WhatIf=$true}).ExitCode | Should -Be 0
        Test-Path $callsPath | Should -BeFalse
    }
    It 'purges only when explicitly requested' {
        (Invoke-DockerFixture '13.docker.ollama.user.stop.ps1' @{ComposePath=$composePath;Action='Purge';Confirm=$false}).ExitCode | Should -Be 0
        (Get-Content $callsPath | ConvertFrom-Json) | Should -Contain '--volumes'
    }
    It 'preserves an existing Compose file and waits for services' {
        $before = (Get-FileHash $composePath).Hash
        (Invoke-DockerFixture '13.docker.ollama.user.ps1' @{ComposePath=$composePath}).ExitCode | Should -Be 0
        (Get-FileHash $composePath).Hash | Should -Be $before
        $calls = @(Get-Content $callsPath)
        $calls | Should -HaveCount 2
        ($calls[1] | ConvertFrom-Json) | Should -Contain '--wait'
    }
    It 'rejects unrelated Compose files without modifying them or running Docker' {
        Set-Content $composePath 'services: {}'
        $before = (Get-FileHash $composePath).Hash
        (Invoke-DockerFixture '13.docker.ollama.user.ps1' @{ComposePath=$composePath}).ExitCode | Should -Be 1
        Test-Path $callsPath | Should -BeFalse
        (Get-FileHash $composePath).Hash | Should -Be $before
    }
    It 'propagates Docker failures without a success message' {
        $result = Invoke-DockerFixture '13.docker.ollama.user.ps1' @{ComposePath=$composePath} -Failure 17
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Not -Match 'reached running/healthy'
        @(Get-Content $callsPath) | Should -HaveCount 1
        $result = Invoke-DockerFixture '13.docker.ollama.user.stop.ps1' @{ComposePath=$composePath} -Failure 17
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Not -Match 'completed successfully'
    }
    It 'retires direct container replacement without invoking Docker' {
        (Invoke-DockerFixture 'Start-OllamaAndWebUI.ps1' @{}).ExitCode | Should -Be 1
        Test-Path $callsPath | Should -BeFalse
    }
}
