BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    . "$repositoryRoot/setup-scripts/setup-functions.ps1"
    . "$repositoryRoot/setup-scripts/configuration-ui.ps1"
}

Describe 'Keyboard selection' {
    It 'toggles choices and preserves catalog order' {
        $keys = [Collections.Generic.Queue[string]]::new()
        @('DownArrow', 'Spacebar', 'UpArrow', 'Spacebar', 'End', 'Spacebar', 'Enter') | ForEach-Object { $keys.Enqueue($_) }
        $result = @(Read-DotfilesMultiSelection -Choices @('base', 'dev', 'wsl') -CurrentValues @('base') `
            -ReadKey { $keys.Dequeue() } -Render { })
        ($result -join ',') | Should -Be 'dev,wsl'
    }
    It 'can select all then clear all without returning null entries' {
        $keys = [Collections.Generic.Queue[string]]::new()
        @('A', 'N', 'Enter') | ForEach-Object { $keys.Enqueue($_) }
        $result = @(Read-DotfilesMultiSelection -Choices @('base', 'dev') -ReadKey { $keys.Dequeue() } -Render { })
        $result | Should -HaveCount 0
        ConvertTo-Json -InputObject $result -Compress | Should -Be '[]'
    }
    It 'wraps navigation and returns a single selection as an array at the caller' {
        $keys = [Collections.Generic.Queue[string]]::new()
        @('UpArrow', 'Spacebar', 'Enter') | ForEach-Object { $keys.Enqueue($_) }
        $result = @(Read-DotfilesMultiSelection -Choices @('base', 'dev') -ReadKey { $keys.Dequeue() } -Render { })
        $result | Should -HaveCount 1
        $result[0] | Should -Be dev
    }
    It 'cancels without returning edited choices' {
        { Read-DotfilesMultiSelection -Choices @('base') -ReadKey { 'Escape' } -Render { } } | Should -Throw '*cancelled*'
    }
    It 'does not request input for an empty catalog' {
        @(Read-DotfilesMultiSelection -Choices @() -ReadKey { throw 'Unexpected input' } -Render { }) | Should -HaveCount 0
    }
}

Describe 'Configuration round trip' {
    AfterEach { Remove-Variable dotfilesUiTestAnswers -Scope Global -ErrorAction SilentlyContinue }
    BeforeEach {
        $configDirectory = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $configDirectory
        Get-ChildItem "$repositoryRoot/dotfiles-configurations/*.example" | Copy-Item -Destination $configDirectory
        & "$repositoryRoot/setup-scripts/configure.ps1" -ConfigDirectory $configDirectory -NonInteractive
        $global:dotfilesUiTestAnswers = [Collections.Generic.Queue[string]]::new()
        Mock Read-Host {
            param($Prompt)
            if ($Prompt -like 'Choose comma-separated*') { return $global:dotfilesUiTestAnswers.Dequeue() }
            return ''
        }
    }
    It 'persists four empty arrays and passes preflight after selecting none' {
        1..4 | ForEach-Object { $global:dotfilesUiTestAnswers.Enqueue('none') }
        & "$repositoryRoot/setup-scripts/configure.ps1" -ConfigDirectory $configDirectory -TextMode
        $bootstrap = Read-DotfilesConfigurationObject (Join-Path $configDirectory 'dotfiles-bootstrap-variables.json')
        foreach ($selector in @('INSTALL_PACKAGES', 'INSTALL_FEATURES', 'INSTALL_CAPABILITIES', 'INSTALL_SETTINGS')) {
            $bootstrap.$selector -is [array] | Should -BeTrue
            $bootstrap.$selector | Should -HaveCount 0
        }
        { Assert-DotfilesSetupConfiguration -DotfilesVariables $bootstrap -ConfigDirectory $configDirectory `
            -ModuleDirectory "$repositoryRoot/setup-modules" } | Should -Not -Throw
    }
    It 'retains an existing empty selection when Enter is pressed' {
        $path = Join-Path $configDirectory 'dotfiles-bootstrap-variables.json'
        $bootstrap = Read-DotfilesConfigurationObject $path
        foreach ($selector in @('INSTALL_PACKAGES', 'INSTALL_FEATURES', 'INSTALL_CAPABILITIES', 'INSTALL_SETTINGS')) { $bootstrap.$selector = @() }
        $bootstrap | ConvertTo-Json -Depth 20 | Set-Content $path
        1..4 | ForEach-Object { $global:dotfilesUiTestAnswers.Enqueue('') }
        & "$repositoryRoot/setup-scripts/configure.ps1" -ConfigDirectory $configDirectory -TextMode
        (Read-DotfilesConfigurationObject $path).INSTALL_FEATURES -is [array] | Should -BeTrue
    }
    It 'preserves existing files byte for byte when cancelled' {
        $path = Join-Path $configDirectory 'dotfiles-bootstrap-variables.json'
        $before = (Get-FileHash $path).Hash
        $global:dotfilesUiTestAnswers.Enqueue('cancel')
        { & "$repositoryRoot/setup-scripts/configure.ps1" -ConfigDirectory $configDirectory -TextMode } | Should -Throw '*cancelled*'
        (Get-FileHash $path).Hash | Should -Be $before
    }
    It 'validates all edited values before writing either configuration' {
        $path = Join-Path $configDirectory 'dotfiles-bootstrap-variables.json'
        $bootstrap = Read-DotfilesConfigurationObject $path
        $before = (Get-FileHash $path).Hash
        $bootstrap.INSTALL_FEATURES = @('unknown-group')
        { Save-DotfilesConfiguration -ConfigDirectory $configDirectory -ModuleDirectory "$repositoryRoot/setup-modules" `
            -Bootstrap $bootstrap -GitConfig ([pscustomobject]@{'user.name'='Changed'}) } | Should -Throw '*Unknown selection*'
        (Get-FileHash $path).Hash | Should -Be $before
    }
    It 'reprompts invalid text input without silently clearing selections' {
        $global:dotfilesUiTestAnswers.Enqueue('invalid')
        $global:dotfilesUiTestAnswers.Enqueue('')
        $result = @(Read-DotfilesMultiSelection -Choices @('base', 'dev') -CurrentValues @('base') -TextMode)
        $result | Should -HaveCount 1
        $result[0] | Should -Be base
    }
}
