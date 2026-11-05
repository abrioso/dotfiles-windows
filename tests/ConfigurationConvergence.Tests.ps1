Describe 'Exact configuration convergence' {
    BeforeAll {
        $root = Split-Path -Parent $PSScriptRoot
        $hostPath = (Get-Process -Id $PID).Path
    }
    It 'corrects case-only Git values and replaces duplicate entries' {
        $previous = $env:GIT_CONFIG_GLOBAL
        try {
            $env:GIT_CONFIG_GLOBAL = Join-Path $TestDrive 'global.gitconfig'
            git config --global user.name 'andre'
            git config --global --add user.name 'Other'
            $config = Join-Path $TestDrive 'git.json'
            Set-Content $config '{"user.name":"Andre"}'
            & $hostPath -NoProfile -File "$root/setup-modules/Apply-GitConfig.ps1" -ConfigPath $config
            $LASTEXITCODE | Should -Be 0
            $values = @(git config --global --get-all user.name)
            $values | Should -HaveCount 1
            $values[0] | Should -BeExactly 'Andre'
            $before = (Get-FileHash $env:GIT_CONFIG_GLOBAL).Hash
            & $hostPath -NoProfile -File "$root/setup-modules/Apply-GitConfig.ps1" -ConfigPath $config
            $LASTEXITCODE | Should -Be 0
            (Get-FileHash $env:GIT_CONFIG_GLOBAL).Hash | Should -Be $before
            git config --global user.name 'andre'
            & $hostPath -NoProfile -File "$root/setup-modules/Apply-GitConfig.ps1" -ConfigPath $config
            $LASTEXITCODE | Should -Be 0
            (git config --global user.name) | Should -BeExactly 'Andre'
        } finally { $env:GIT_CONFIG_GLOBAL = $previous }
    }
    It 'corrects case-only user environment values and converges on reapply' -Skip:([Environment]::OSVersion.Platform -ne 'Win32NT') {
        $name = 'DOTFILES_TEST_' + [guid]::NewGuid().ToString('N')
        try {
            [Environment]::SetEnvironmentVariable($name, 'oldCase', 'User')
            $config = Join-Path $TestDrive 'env.json'
            @{EnvironmentVariables=@(@{Name=$name;Value='OldCase';Scope='User'})} | ConvertTo-Json -Depth 5 | Set-Content $config
            1..2 | ForEach-Object {
                & $hostPath -NoProfile -File "$root/setup-modules/Set-EnvironmentVariables.ps1" -ConfigPath $config
                $LASTEXITCODE | Should -Be 0
                [Environment]::GetEnvironmentVariable($name, 'User') | Should -BeExactly 'OldCase'
            }
        } finally { [Environment]::SetEnvironmentVariable($name, $null, 'User') }
    }
}
