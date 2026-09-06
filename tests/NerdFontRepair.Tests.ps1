Describe 'Nerd Font installation completeness' {
    BeforeAll {
        $path = Join-Path (Split-Path -Parent $PSScriptRoot) 'setup-modules/Install-NerdFont.ps1'
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$null)
        $definition = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Test-DotfilesNerdFontInstallation' }, $true)
        . ([scriptblock]::Create($definition.Extent.Text))
    }
    It 'repairs missing files, corrupt files and missing registration' {
        $font = Join-Path $TestDrive 'CaskaydiaCove.ttf'
        Set-Content $font 'font bytes'
        $state = Join-Path $TestDrive 'state.json'
        @{ Version = 1; Fonts = @(@{ Name = 'CaskaydiaCove.ttf'; Hash = (Get-FileHash $font).Hash }) } | ConvertTo-Json -Depth 4 | Set-Content $state
        Mock Get-ItemProperty { [pscustomobject]@{ 'CaskaydiaCove (TrueType)' = $font } }
        Test-DotfilesNerdFontInstallation $state $TestDrive 'test-registry' | Should -BeTrue
        Set-Content $font 'corrupt bytes'
        Test-DotfilesNerdFontInstallation $state $TestDrive 'test-registry' | Should -BeFalse
        Set-Content $font 'font bytes'
        Mock Get-ItemProperty { [pscustomobject]@{} }
        Test-DotfilesNerdFontInstallation $state $TestDrive 'test-registry' | Should -BeFalse
        Remove-Item $font
        Test-DotfilesNerdFontInstallation $state $TestDrive 'test-registry' | Should -BeFalse
    }
    It 'does not treat a legacy partial installation as complete' {
        Set-Content (Join-Path $TestDrive 'CaskaydiaCove.ttf') 'partial legacy install'
        Test-DotfilesNerdFontInstallation (Join-Path $TestDrive 'absent.json') $TestDrive 'test-registry' | Should -BeFalse
    }
}

Describe 'Nerd Font file installation' {
    BeforeAll {
        $path = Join-Path (Split-Path -Parent $PSScriptRoot) 'setup-modules/Install-NerdFont.ps1'
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$null)
        $definition = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Install-DotfilesNerdFontFile' }, $true)
        . ([scriptblock]::Create($definition.Extent.Text))
    }
    BeforeEach {
        $sourceDirectory = New-Item -ItemType Directory -Path (Join-Path $TestDrive ([guid]::NewGuid().ToString('N')))
        $destinationDirectory = New-Item -ItemType Directory -Path (Join-Path $TestDrive ([guid]::NewGuid().ToString('N')))
        $sourcePath = Join-Path $sourceDirectory.FullName 'CaskaydiaCove.ttf'
        $destinationPath = Join-Path $destinationDirectory.FullName 'CaskaydiaCove.ttf'
        Set-Content -LiteralPath $sourcePath 'font bytes'
        $sourceFont = Get-Item -LiteralPath $sourcePath
        Mock New-ItemProperty {}
    }
    It 'reuses an identical font held open without write sharing and repairs registration' {
        Copy-Item -LiteralPath $sourcePath -Destination $destinationPath
        $handle = [IO.File]::Open($destinationPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        try {
            $result = Install-DotfilesNerdFontFile $sourceFont $destinationDirectory.FullName 'test-registry'
            $result.Hash | Should -Be (Get-FileHash -LiteralPath $sourcePath).Hash
            Should -Invoke New-ItemProperty -Times 1 -Exactly -ParameterFilter {
                $Name -eq 'CaskaydiaCove (TrueType)' -and $Value -eq $destinationPath
            }
        } finally { $handle.Dispose() }
    }
    It 'installs a missing file and replaces a corrupt file' {
        Install-DotfilesNerdFontFile $sourceFont $destinationDirectory.FullName 'test-registry'
        (Get-FileHash -LiteralPath $destinationPath).Hash | Should -Be (Get-FileHash -LiteralPath $sourcePath).Hash
        Set-Content -LiteralPath $destinationPath 'corrupt bytes'
        Install-DotfilesNerdFontFile $sourceFont $destinationDirectory.FullName 'test-registry'
        (Get-FileHash -LiteralPath $destinationPath).Hash | Should -Be (Get-FileHash -LiteralPath $sourcePath).Hash
    }
    It 'reports a changed locked font without registering it as installed' {
        Set-Content -LiteralPath $destinationPath 'older font bytes'
        $handle = [IO.File]::Open($destinationPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        try {
            { Install-DotfilesNerdFontFile $sourceFont $destinationDirectory.FullName 'test-registry' } |
                Should -Throw '*needs replacement but is in use*'
            Should -Invoke New-ItemProperty -Times 0 -Exactly
            (Get-Content -LiteralPath $destinationPath -Raw).Trim() | Should -Be 'older font bytes'
        } finally { $handle.Dispose() }
    }
    It 'propagates registration errors' {
        Mock New-ItemProperty { throw 'registry write denied' }
        { Install-DotfilesNerdFontFile $sourceFont $destinationDirectory.FullName 'test-registry' } |
            Should -Throw '*registry write denied*'
    }
}
