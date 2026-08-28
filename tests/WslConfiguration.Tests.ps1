Describe 'WSL 2 state enforcement' {
    BeforeEach {
        $global:DotfilesWslTestCalls = [System.Collections.Generic.List[string]]::new()
        $global:DotfilesWslTestQuietOutput = @()
        $global:DotfilesWslTestVerboseOutput = @()
        function global:Test-DotfilesWslCommand {
            $global:DotfilesWslTestCalls.Add(($args -join ' '))
            $global:LASTEXITCODE = 0
            if ($args.Count -ge 2 -and $args[0] -eq '--list' -and $args[1] -eq '--quiet') {
                return $global:DotfilesWslTestQuietOutput
            }
            if ($args.Count -ge 2 -and $args[0] -eq '--list' -and $args[1] -eq '--verbose') {
                return $global:DotfilesWslTestVerboseOutput
            }
        }
    }

    AfterEach {
        Remove-Item -Path Function:/Test-DotfilesWslCommand -ErrorAction SilentlyContinue
        Remove-Variable -Name DotfilesWslTestCalls -Scope Global -ErrorAction SilentlyContinue
        Remove-Variable -Name DotfilesWslTestQuietOutput -Scope Global -ErrorAction SilentlyContinue
        Remove-Variable -Name DotfilesWslTestVerboseOutput -Scope Global -ErrorAction SilentlyContinue
    }

    It 'sets WSL 2 as default and converts an existing WSL 1 Ubuntu registration' {
        $global:DotfilesWslTestQuietOutput = @("U`0buntu")
        $global:DotfilesWslTestVerboseOutput = @("  N`0AME      STATE      VERSION", "*`0 Ubuntu    Stopped    1`0")
        $modulePath = Join-Path $PSScriptRoot '../setup-modules/Configure-WSL2.ps1'

        & $modulePath -WslCommand 'Test-DotfilesWslCommand' -DistributionName 'Ubuntu'

        $expected = @('--set-default-version 2', '--list --quiet', '--list --verbose', '--set-version Ubuntu 2')
        if (($global:DotfilesWslTestCalls -join ',') -ne ($expected -join ',')) {
            throw "Expected WSL calls '$($expected -join ',')', got '$($global:DotfilesWslTestCalls -join ',')'."
        }
    }

    It 'leaves an existing WSL 2 Ubuntu registration unchanged' {
        $global:DotfilesWslTestQuietOutput = @('Ubuntu')
        $global:DotfilesWslTestVerboseOutput = @('  NAME      STATE      VERSION', '* Ubuntu    Running    2')
        $modulePath = Join-Path $PSScriptRoot '../setup-modules/Configure-WSL2.ps1'

        & $modulePath -WslCommand 'Test-DotfilesWslCommand' -DistributionName 'Ubuntu'

        $expected = @('--set-default-version 2', '--list --quiet', '--list --verbose')
        if (($global:DotfilesWslTestCalls -join ',') -ne ($expected -join ',')) {
            throw "Expected WSL calls '$($expected -join ',')', got '$($global:DotfilesWslTestCalls -join ',')'."
        }
    }

    It 'does not treat a prefixed distro name as the configured Ubuntu distro' {
        $global:DotfilesWslTestQuietOutput = @('Ubuntu Custom')
        $global:DotfilesWslTestVerboseOutput = @('  NAME              STATE      VERSION', '  Ubuntu Custom     Stopped    1')
        $modulePath = Join-Path $PSScriptRoot '../setup-modules/Configure-WSL2.ps1'

        & $modulePath -WslCommand 'Test-DotfilesWslCommand' -DistributionName 'Ubuntu'

        $expected = @('--set-default-version 2', '--list --quiet')
        if (($global:DotfilesWslTestCalls -join ',') -ne ($expected -join ',')) {
            throw "Expected WSL calls '$($expected -join ',')', got '$($global:DotfilesWslTestCalls -join ',')'."
        }
    }

    It 'sets the WSL 2 default without converting an unregistered Ubuntu package' {
        $global:DotfilesWslTestQuietOutput = @('Debian')
        $global:DotfilesWslTestVerboseOutput = @('  NAME      STATE      VERSION', '  Debian    Stopped    2')
        $modulePath = Join-Path $PSScriptRoot '../setup-modules/Configure-WSL2.ps1'

        & $modulePath -WslCommand 'Test-DotfilesWslCommand' -DistributionName 'Ubuntu'

        $expected = @('--set-default-version 2', '--list --quiet')
        if (($global:DotfilesWslTestCalls -join ',') -ne ($expected -join ',')) {
            throw "Expected WSL calls '$($expected -join ',')', got '$($global:DotfilesWslTestCalls -join ',')'."
        }
    }
}
