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

    It 'checks the parent profile before resolving an alias name' {
        $setupPath = Join-Path $PSScriptRoot '../setup-scripts/setup.ps1'
        $setupText = Get-Content -LiteralPath $setupPath -Raw
        $profileReadIndex = $setupText.IndexOf("GetEnvironmentVariable('USERPROFILE', 'Process')")
        $asciiCheckIndex = $setupText.IndexOf('$hasNonAsciiCharacter =', $profileReadIndex)
        $resolverIndex = $setupText.IndexOf('Resolve-DotfilesUserHomeAliasName', $asciiCheckIndex)

        $profileReadIndex | Should -BeGreaterOrEqual 0
        $asciiCheckIndex | Should -BeGreaterThan $profileReadIndex
        $resolverIndex | Should -BeGreaterThan $asciiCheckIndex
    }

    It 'routes parent alias derivation through the tested resolver' {
        $setupPath = Join-Path $PSScriptRoot '../setup-scripts/setup.ps1'
        $setupText = Get-Content -LiteralPath $setupPath -Raw
        $expectedCall = 'Resolve-DotfilesUserHomeAliasName -WindowsIdentityName $windowsIdentityName -UserName $env:USERNAME'

        $setupText | Should -Match ([regex]::Escape($expectedCall))
    }

    Context 'conditional elevation preflight' {
        It 'skips an ASCII-only profile without probing the alias path' {
            Mock Get-Item { throw 'Alias path must not be probed for an ASCII profile.' }

            $result = Get-DotfilesUserHomeAliasPreflight `
                -UserProfile 'C:\Users\akbrioso' `
                -AliasName 'akbrioso' `
                -CurrentHome 'anything'

            $result.Action | Should -BeExactly 'Skip'
            $result.AliasPath | Should -BeNullOrEmpty
            Should -Invoke Get-Item -Times 0 -Exactly
        }

        It 'requests elevation only when the safe alias path is missing' {
            Mock Get-Item { throw [System.Management.Automation.ItemNotFoundException]::new('missing') }

            $result = Get-DotfilesUserHomeAliasPreflight `
                -UserProfile 'C:\Users\AndréKakooBrioso' `
                -AliasName 'akbrioso' `
                -CurrentHome $null

            $result.Action | Should -BeExactly 'Elevate'
            $result.AliasPath | Should -BeExactly 'C:\Users\akbrioso'
        }

        It 'runs non-elevated when the correct junction exists but HOME needs an update' {
            Mock Get-Item {
                [pscustomobject]@{
                    Attributes = [IO.FileAttributes]::Directory -bor [IO.FileAttributes]::ReparsePoint
                    LinkType = 'Junction'
                    Target = 'C:\Users\AndréKakooBrioso'
                }
            }

            $result = Get-DotfilesUserHomeAliasPreflight `
                -UserProfile 'C:\Users\AndréKakooBrioso' `
                -AliasName 'akbrioso' `
                -CurrentHome 'C:\Users\old-home'

            $result.Action | Should -BeExactly 'RunNonElevated'
        }

        It 'skips the module when both the junction and user HOME are correct' {
            Mock Get-Item {
                [pscustomobject]@{
                    Attributes = [IO.FileAttributes]::Directory -bor [IO.FileAttributes]::ReparsePoint
                    LinkType = 'Junction'
                    Target = 'C:\Users\AndréKakooBrioso'
                }
            }

            $result = Get-DotfilesUserHomeAliasPreflight `
                -UserProfile 'C:\Users\AndréKakooBrioso' `
                -AliasName 'akbrioso' `
                -CurrentHome 'C:\Users\akbrioso'

            $result.Action | Should -BeExactly 'Skip'
        }

        It 'fails closed when the alias path cannot be inspected' {
            Mock Get-Item { throw [System.UnauthorizedAccessException]::new('denied') }

            $result = Get-DotfilesUserHomeAliasPreflight `
                -UserProfile 'C:\Users\AndréKakooBrioso' `
                -AliasName 'akbrioso' `
                -CurrentHome $null

            $result.Action | Should -BeExactly 'Fail'
            $result.Message | Should -Match 'Cannot inspect'
        }

        It 'fails closed for an existing regular path, wrong link type, or wrong target' -ForEach @(
            @{
                ExistingItem = [pscustomobject]@{
                    Attributes = [IO.FileAttributes]::Directory
                    LinkType = $null
                    Target = $null
                }
            }
            @{
                ExistingItem = [pscustomobject]@{
                    Attributes = [IO.FileAttributes]::Directory -bor [IO.FileAttributes]::ReparsePoint
                    LinkType = 'SymbolicLink'
                    Target = 'C:\Users\AndréKakooBrioso'
                }
            }
            @{
                ExistingItem = [pscustomobject]@{
                    Attributes = [IO.FileAttributes]::Directory -bor [IO.FileAttributes]::ReparsePoint
                    LinkType = 'Junction'
                    Target = 'C:\Users\SomeoneElse'
                }
            }
        ) {
            Mock Get-Item { return $ExistingItem }

            $result = Get-DotfilesUserHomeAliasPreflight `
                -UserProfile 'C:\Users\AndréKakooBrioso' `
                -AliasName 'akbrioso' `
                -CurrentHome $null

            $result.Action | Should -BeExactly 'Fail'
        }

        It 'requests child creation when the explicit expected alias is still missing' {
            Mock Get-Item { throw [System.Management.Automation.ItemNotFoundException]::new('missing') }

            $result = Get-DotfilesUserHomeAliasJunctionPreflight `
                -UserProfile 'C:\Users\AndréKakooBrioso' `
                -AliasPath 'C:\Users\akbrioso'

            $result.Action | Should -BeExactly 'Elevate'
        }

        It 'lets the child no-op successfully when the explicit alias became the correct junction' {
            Mock Get-Item {
                [pscustomobject]@{
                    Attributes = [IO.FileAttributes]::Directory -bor [IO.FileAttributes]::ReparsePoint
                    LinkType = 'Junction'
                    Target = 'C:\Users\AndréKakooBrioso'
                }
            }

            $result = Get-DotfilesUserHomeAliasJunctionPreflight `
                -UserProfile 'C:\Users\AndréKakooBrioso' `
                -AliasPath 'C:\Users\akbrioso'

            $result.Action | Should -BeExactly 'Skip'
        }

        It 'fails child revalidation for a collision, wrong target, or inspection error' -ForEach @(
            @{
                Probe = {
                    [pscustomobject]@{
                        Attributes = [IO.FileAttributes]::Directory
                        LinkType = $null
                        Target = $null
                    }
                }
            }
            @{
                Probe = {
                    [pscustomobject]@{
                        Attributes = [IO.FileAttributes]::Directory -bor [IO.FileAttributes]::ReparsePoint
                        LinkType = 'Junction'
                        Target = 'C:\Users\DifferentUser'
                    }
                }
            }
            @{
                Probe = { throw [System.UnauthorizedAccessException]::new('denied') }
            }
        ) {
            Mock Get-Item $Probe

            $result = Get-DotfilesUserHomeAliasJunctionPreflight `
                -UserProfile 'C:\Users\AndréKakooBrioso' `
                -AliasPath 'C:\Users\akbrioso'

            $result.Action | Should -BeExactly 'Fail'
        }

        It 'fails child preflight when the supplied alias is not the profile sibling recomputed from its leaf' {
            Mock Get-Item { throw 'A mismatched alias must fail before probing.' }

            $result = Get-DotfilesUserHomeAliasJunctionPreflight `
                -UserProfile 'C:\Users\AndréKakooBrioso' `
                -AliasPath 'D:\Elsewhere\akbrioso'

            $result.Action | Should -BeExactly 'Fail'
            $result.Message | Should -Match 'does not match expected alias path'
            Should -Invoke Get-Item -Times 0 -Exactly
        }

    }

    Context 'setup orchestration contract' {
        It 'declares the home alias module administrative and dynamically overrides it from preflight' {
            $configPath = Join-Path $PSScriptRoot '../dotfiles-configurations/setup-modules.json.example'
            $setupPath = Join-Path $PSScriptRoot '../setup-scripts/setup.ps1'
            $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
            $setup = Get-Content -LiteralPath $setupPath -Raw
            $homeModule = @($config.settings.base | Where-Object { $_.script -eq 'Set-UserHomeAlias.ps1' })[0]

            $homeModule.requiresAdmin | Should -BeTrue
            $preflightIndex = $setup.IndexOf('Get-DotfilesUserHomeAliasPreflight')
            $elevationIndex = $setup.IndexOf('Start-Process -FilePath $moduleHost')
            $preflightIndex | Should -BeGreaterOrEqual 0
            $elevationIndex | Should -BeGreaterThan $preflightIndex
            $setup | Should -Match ':moduleLoop\s+foreach\s*\(\$module\s+in\s+\$modulesToRun\)'
            $setup | Should -Match "'Skip'[\s\S]*?continue\s+moduleLoop"
            $setup | Should -Match "'RunNonElevated'[\s\S]*?\`$requiresAdmin\s*=\s*\`$false"
            $setup | Should -Match "'Elevate'[\s\S]*?\`$requiresAdmin\s*=\s*\`$true"
            $setup | Should -Match "'Fail'[\s\S]*?throw"
        }

        It 'gives the detached home alias child a unique explicit transcript and reports it on failure' {
            $modulePath = Join-Path $PSScriptRoot '../setup-modules/Set-UserHomeAlias.ps1'
            $setupPath = Join-Path $PSScriptRoot '../setup-scripts/setup.ps1'
            $module = Get-Content -LiteralPath $modulePath -Raw
            $setup = Get-Content -LiteralPath $setupPath -Raw

            $module | Should -Match 'param\s*\([\s\S]*?\[string\]\$LogFilePath'
            $module | Should -Match 'Start-Logging\s+-LogFilePath\s+\$LogFilePath\s+-PassThru\s+-RequireRequestedPath'
            $module | Should -Match 'finally\s*\{[\s\S]*?Stop-Logging[\s\S]*?\}'
            $module | Should -Match 'exit \$moduleExitCode'
            $setup | Should -Match "Set-UserHomeAlias\.ps1'[\s\S]*?NewGuid"
            $setup | Should -Match "Set-UserHomeAlias\.ps1'[\s\S]*?'-LogFilePath',\s*\`$moduleLogFile"
            $setup | Should -Match 'Write-ModuleLogLocation\s+-ModuleLogFile\s+\$moduleLogFile'
        }

        It 'isolates the elevated junction child from the alternate administrator identity and user environment' {
            $modulePath = Join-Path $PSScriptRoot '../setup-modules/Set-UserHomeAlias.ps1'
            $module = Get-Content -LiteralPath $modulePath -Raw

            $module | Should -Match '(?s)param\s*\(.*\[Parameter\(Mandatory\)\]\s*\[string\]\$UserProfile.*\[Parameter\(Mandatory\)\]\s*\[string\]\$AliasPath'
            $module | Should -Not -Match "GetEnvironmentVariable\('USERPROFILE'"
            $module | Should -Not -Match "GetEnvironmentVariable\('HOME'"
            $module | Should -Not -Match 'SetEnvironmentVariable'
            $module | Should -Not -Match 'WindowsIdentity|Resolve-DotfilesUserHomeAliasName|USERNAME'
        }

        It 'makes the parent own HOME updates and passes explicit quoted paths only to an elevated junction child' {
            $setupPath = Join-Path $PSScriptRoot '../setup-scripts/setup.ps1'
            $setup = Get-Content -LiteralPath $setupPath -Raw

            $setup | Should -Match "(?s)'RunNonElevated'\s*\{.*SetEnvironmentVariable\('HOME',\s*\`$homeAliasPreflight.AliasPath,\s*'User'\).*continue\s+moduleLoop"
            $setup | Should -Match "(?s)'Elevate'\s*\{.*\`$requiresAdmin\s*=\s*\`$true"
            $setup | Should -Match "\`$moduleArguments\s*\+=\s*@\('-UserProfile',\s*\`$userProfile,\s*'-AliasPath',\s*\`$homeAliasPreflight.AliasPath\)"
            $setup | Should -Match '-UserProfile\s+`"\$userProfile`"\s+-AliasPath\s+`"\$\(\$homeAliasPreflight.AliasPath\)`"'
            $setup | Should -Match "(?s)if\s*\(\`$moduleExitCode\s+-eq\s+0\).*SetEnvironmentVariable\('HOME',\s*\`$homeAliasPreflight.AliasPath,\s*'User'\)"
        }

        It 'updates process HOME after a non-elevated persisted HOME update' {
            $setupPath = Join-Path $PSScriptRoot '../setup-scripts/setup.ps1'
            $setup = Get-Content -LiteralPath $setupPath -Raw

            $setup | Should -Match "(?s)'RunNonElevated'\s*\{.*SetEnvironmentVariable\('HOME',\s*\`$homeAliasPreflight.AliasPath,\s*'User'\).*SetEnvironmentVariable\('HOME',\s*\`$homeAliasPreflight.AliasPath,\s*'Process'\).*continue\s+moduleLoop"
        }

        It 'updates process HOME on Skip only when preflight returned a persisted alias path' {
            $setupPath = Join-Path $PSScriptRoot '../setup-scripts/setup.ps1'
            $setup = Get-Content -LiteralPath $setupPath -Raw

            $setup | Should -Match "(?s)'Skip'\s*\{.*if\s*\(\`$homeAliasPreflight.AliasPath\)\s*\{.*SetEnvironmentVariable\('HOME',\s*\`$homeAliasPreflight.AliasPath,\s*'Process'\).*\}.*continue\s+moduleLoop"
        }

        It 'updates process HOME after successful elevated alias creation' {
            $setupPath = Join-Path $PSScriptRoot '../setup-scripts/setup.ps1'
            $setup = Get-Content -LiteralPath $setupPath -Raw

            $setup | Should -Match "(?s)if\s*\(\`$moduleExitCode\s+-eq\s+0\)\s*\{\s*if\s*\(\`$moduleName\s+-eq\s+'Set-UserHomeAlias.ps1'\).*SetEnvironmentVariable\('HOME',\s*\`$homeAliasPreflight.AliasPath,\s*'User'\).*SetEnvironmentVariable\('HOME',\s*\`$homeAliasPreflight.AliasPath,\s*'Process'\)"
        }

        It 'makes the elevated child revalidate explicit paths and create only for Elevate' {
            $modulePath = Join-Path $PSScriptRoot '../setup-modules/Set-UserHomeAlias.ps1'
            $module = Get-Content -LiteralPath $modulePath -Raw

            $module | Should -Match 'Get-DotfilesUserHomeAliasJunctionPreflight\s+`?\s*-UserProfile\s+\$UserProfile\s+`?\s*-AliasPath\s+\$AliasPath'
            $module | Should -Match "(?s)switch\s*\(\`$preflight.Action\).*'Elevate'\s*\{.*New-Item.*'Skip'\s*\{.*'Fail'\s*\{.*throw"
        }
    }
}
