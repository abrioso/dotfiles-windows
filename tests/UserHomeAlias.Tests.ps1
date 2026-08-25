Describe 'User home alias resolution' {
    BeforeAll {
        . "$PSScriptRoot/../setup-scripts/setup-functions.ps1"
    }

    Context 'whoami UPN result validation' {
        It 'accepts trimmed UPN output only for a successful exit code' {
            ConvertFrom-DotfilesWhoAmIUpnResult -Output "  akbrioso@contoso.com`r`n" -ExitCode 0 |
                Should -BeExactly 'akbrioso@contoso.com'
        }

        It 'rejects nonzero exit codes, malformed output, and multiple output records' {
            ConvertFrom-DotfilesWhoAmIUpnResult -Output 'akbrioso@contoso.com' -ExitCode 1 |
                Should -BeNullOrEmpty
            ConvertFrom-DotfilesWhoAmIUpnResult -Output 'AzureAD\akbrioso' -ExitCode 0 |
                Should -BeNullOrEmpty
            ConvertFrom-DotfilesWhoAmIUpnResult -Output @('akbrioso@', 'contoso.com') -ExitCode 0 |
                Should -BeNullOrEmpty
            ConvertFrom-DotfilesWhoAmIUpnResult -Output "akbrioso@contoso.com`nsecond@contoso.com" -ExitCode 0 |
                Should -BeNullOrEmpty
        }
    }

    It 'prefers the signed-in UPN local part over Entra-qualified identity and display-name USERNAME values' {
        Mock Get-DotfilesSignedInUserUpn { 'akbrioso@contoso.com' }

        $aliasName = Resolve-DotfilesUserHomeAliasName `
            -WindowsIdentityName 'AzureAD\AndréKakooBrioso' `
            -UserName 'AndréKakooBrioso'

        $aliasName | Should -BeExactly 'akbrioso'
    }

    It 'uses a valid Windows identity UPN when whoami cannot provide one' {
        Mock Get-DotfilesSignedInUserUpn { $null }

        $aliasName = Resolve-DotfilesUserHomeAliasName `
            -WindowsIdentityName 'fallback@contoso.com' `
            -UserName 'DisplayName'

        $aliasName | Should -BeExactly 'fallback'
    }

    It 'uses a valid USERNAME leaf when neither UPN source is available' {
        Mock Get-DotfilesSignedInUserUpn { $null }

        $aliasName = Resolve-DotfilesUserHomeAliasName `
            -WindowsIdentityName 'AzureAD\DisplayName' `
            -UserName 'safe-name'

        $aliasName | Should -BeExactly 'safe-name'
    }

    It 'falls through when the whoami UPN local part is not a safe path leaf' {
        Mock Get-DotfilesSignedInUserUpn { '../escape@contoso.com' }

        $aliasName = Resolve-DotfilesUserHomeAliasName `
            -WindowsIdentityName 'fallback@contoso.com' `
            -UserName 'DisplayName'

        $aliasName | Should -BeExactly 'fallback'
    }

    It 'rejects path separators and dot-only USERNAME values' -ForEach @(
        @{ InvalidName = '../escape' }
        @{ InvalidName = '..\escape' }
        @{ InvalidName = '.' }
        @{ InvalidName = '..' }
        @{ InvalidName = '...' }
    ) {
        Mock Get-DotfilesSignedInUserUpn { $null }

        $aliasName = Resolve-DotfilesUserHomeAliasName `
            -WindowsIdentityName 'AzureAD\DisplayName' `
            -UserName $InvalidName

        $aliasName | Should -BeNullOrEmpty
    }

    It 'rejects non-ASCII, control, Windows-invalid, trailing dot or space, and DOS device leaves' -ForEach @(
        @{ InvalidName = 'André' }
        @{ InvalidName = "bad`nname" }
        @{ InvalidName = 'bad<name' }
        @{ InvalidName = 'bad>name' }
        @{ InvalidName = 'bad:name' }
        @{ InvalidName = 'bad"name' }
        @{ InvalidName = 'bad|name' }
        @{ InvalidName = 'bad?name' }
        @{ InvalidName = 'bad*name' }
        @{ InvalidName = 'name.' }
        @{ InvalidName = 'name ' }
        @{ InvalidName = ' leading' }
        @{ InvalidName = 'embedded space' }
        @{ InvalidName = 'CON' }
        @{ InvalidName = 'CON .txt' }
        @{ InvalidName = 'CONIN$' }
        @{ InvalidName = 'CONOUT$' }
        @{ InvalidName = 'CLOCK$' }
        @{ InvalidName = 'prn.txt' }
        @{ InvalidName = 'AUX' }
        @{ InvalidName = 'nul.log' }
        @{ InvalidName = 'COM0' }
        @{ InvalidName = 'COM1' }
        @{ InvalidName = 'com9.txt' }
        @{ InvalidName = 'LPT0' }
        @{ InvalidName = 'LPT1' }
        @{ InvalidName = 'lpt9.log' }
    ) {
        Test-DotfilesUserHomeAliasLeaf -Name $InvalidName | Should -BeFalse
    }

    It 'checks for an ASCII-only profile before resolving an alias name' {
        $modulePath = Join-Path $PSScriptRoot '../setup-modules/Set-UserHomeAlias.ps1'
        $moduleText = Get-Content -LiteralPath $modulePath -Raw
        $asciiCheckIndex = $moduleText.IndexOf('$isAscii =')
        $resolverIndex = $moduleText.IndexOf('Resolve-DotfilesUserHomeAliasName')

        $asciiCheckIndex | Should -BeGreaterOrEqual 0
        $resolverIndex | Should -BeGreaterThan $asciiCheckIndex
    }

    It 'routes the module alias derivation through the tested resolver' {
        $modulePath = Join-Path $PSScriptRoot '../setup-modules/Set-UserHomeAlias.ps1'
        $moduleText = Get-Content -LiteralPath $modulePath -Raw
        $expectedCall = 'Resolve-DotfilesUserHomeAliasName -WindowsIdentityName $windowsIdentityName -UserName $env:USERNAME'

        $moduleText | Should -Match ([regex]::Escape($expectedCall))
    }
}
