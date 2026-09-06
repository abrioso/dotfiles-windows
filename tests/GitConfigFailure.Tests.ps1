Describe 'Git configuration failures' {
    BeforeAll {
        $modulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'setup-modules/Apply-GitConfig.ps1'
        $hostPath = (Get-Process -Id $PID).Path
    }
    It 'reports failure when Git cannot acquire the configuration lock' {
        $previous = $env:GIT_CONFIG_GLOBAL
        try {
            $env:GIT_CONFIG_GLOBAL = Join-Path $TestDrive 'global.gitconfig'
            Set-Content "$env:GIT_CONFIG_GLOBAL.lock" 'held'
            $config = Join-Path $TestDrive 'git.json'
            Set-Content $config '{"user.name":"Regression Test"}'
            $output = & $hostPath -NoProfile -File $modulePath -ConfigPath $config 2>&1
            $LASTEXITCODE | Should -Be 1
            ($output -join "`n") | Should -Not -Match 'Successfully set'
        } finally { $env:GIT_CONFIG_GLOBAL = $previous }
    }
    It 'fails on an unreadable Git configuration and applies valid settings' {
        $previous = $env:GIT_CONFIG_GLOBAL
        try {
            $env:GIT_CONFIG_GLOBAL = Join-Path $TestDrive 'bad.gitconfig'
            Set-Content $env:GIT_CONFIG_GLOBAL '[invalid'
            $config = Join-Path $TestDrive 'git.json'
            Set-Content $config '{"user.name":"Regression Test"}'
            & $hostPath -NoProfile -File $modulePath -ConfigPath $config 2>&1 | Out-Null
            $LASTEXITCODE | Should -Be 1
            Remove-Item $env:GIT_CONFIG_GLOBAL
            & $hostPath -NoProfile -File $modulePath -ConfigPath $config 2>&1 | Out-Null
            $LASTEXITCODE | Should -Be 0
            (& git config --global user.name) | Should -Be 'Regression Test'
        } finally { $env:GIT_CONFIG_GLOBAL = $previous }
    }
}
