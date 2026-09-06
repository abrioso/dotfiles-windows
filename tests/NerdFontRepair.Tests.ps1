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
