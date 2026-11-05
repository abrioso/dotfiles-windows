BeforeAll {
    $root = Split-Path -Parent $PSScriptRoot
    . "$root/setup-scripts/setup-functions.ps1"
    . "$root/setup-scripts/setup-plan.ps1"
    . "$root/setup-scripts/verify-functions.ps1"
}

Describe 'Read-only WSL probes' {
    It 'distinguishes the default version <Version>' -ForEach @(
        @{Version=2;Expected='Passed'}, @{Version=1;Expected='Drift'}, @{Version=3;Expected='Unknown'}
    ) {
        Mock Get-ItemProperty { [pscustomobject]@{DefaultVersion=$Version} }
        (Get-DotfilesWslDefaultDiagnostic).Status | Should -Be $Expected
    }
    It 'checks registered Ubuntu without launching it' {
        Mock Invoke-DotfilesDiagnosticNative {
            param($Command, $Arguments)
            if ($Arguments -contains '--quiet') { [pscustomobject]@{ExitCode=0;Output="Ubuntu`nOther"} }
            else { [pscustomobject]@{ExitCode=0;Output='* Ubuntu    Running    2'} }
        }
        (Get-DotfilesWslDistributionDiagnostic).Status | Should -Be Passed
        Should -Invoke Invoke-DotfilesDiagnosticNative -Times 2 -Exactly -ParameterFilter { $Arguments -contains '--list' }
    }
    It 'detects WSL 1 and handles unregistered distributions and query failure' {
        Mock Invoke-DotfilesDiagnosticNative {
            param($Command, $Arguments)
            if ($Arguments -contains '--quiet') { [pscustomobject]@{ExitCode=0;Output='Ubuntu'} }
            else { [pscustomobject]@{ExitCode=0;Output='Ubuntu    Stopped    1'} }
        }
        (Get-DotfilesWslDistributionDiagnostic).Status | Should -Be Drift
        Mock Invoke-DotfilesDiagnosticNative { [pscustomobject]@{ExitCode=0;Output='Other'} }
        (Get-DotfilesWslDistributionDiagnostic).Status | Should -Be Skipped
        Mock Invoke-DotfilesDiagnosticNative { [pscustomobject]@{ExitCode=5;Output='private-value'} }
        $result = Get-DotfilesWslDistributionDiagnostic
        $result.Status | Should -Be Unknown
        $result.Message | Should -Not -Match 'private-value'
    }
}

Describe 'Font installed-state probe' {
    BeforeEach {
        $fixture = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path "$fixture/setup-scripts", "$fixture/Microsoft/Windows/Fonts" -Force
        Copy-Item "$root/setup-scripts/downloads.lock.json" "$fixture/setup-scripts"
        $lock = Get-Content "$fixture/setup-scripts/downloads.lock.json" -Raw | ConvertFrom-Json
        $fontPath = Join-Path $fixture 'Microsoft/Windows/Fonts/Test.ttf'
        Set-Content $fontPath 'font-fixture'
        $state = @{Version=1;Release=$lock.CascadiaCode.Release;ArchiveSha256=$lock.CascadiaCode.Sha256;Fonts=@(@{Name='Test.ttf';Hash=(Get-FileHash $fontPath).Hash})}
        $state | ConvertTo-Json -Depth 5 | Set-Content "$fixture/Microsoft/Windows/Fonts/dotfiles-cascadiacode-state.json"
        Mock Test-Path { $true } -ParameterFilter { $LiteralPath -like 'HKCU:*' }
        Mock Get-ItemProperty { [pscustomobject]@{'Test (TrueType)'=$fontPath} }
    }
    It 'certifies recorded files and registration without changing them' {
        $before = (Get-FileHash $fontPath).Hash
        (Get-DotfilesFontDiagnostic $fixture $fixture).Status | Should -Be Passed
        (Get-FileHash $fontPath).Hash | Should -Be $before
    }
    It 'detects a corrupted font and missing registration' {
        Set-Content $fontPath 'corrupted'
        (Get-DotfilesFontDiagnostic $fixture $fixture).Status | Should -Be Drift
        Set-Content $fontPath 'font-fixture'
        Mock Get-ItemProperty { [pscustomobject]@{} }
        (Get-DotfilesFontDiagnostic $fixture $fixture).Status | Should -Be Drift
    }
    It 'reports denied access as Unknown without exposing private details' {
        Mock Get-ItemProperty { throw 'private-path' }
        $checks = [Collections.Generic.List[object]]::new()
        Add-DotfilesDiagnosticCheck $checks Font Test { Get-DotfilesFontDiagnostic $fixture $fixture }
        $checks[0].Status | Should -Be Unknown
        $checks[0].Message | Should -Not -Match 'private-path'
    }
}

Describe 'Home alias probe' {
    It 'skips ASCII profiles and maps alias preflight without disclosing paths' {
        (Get-DotfilesHomeDiagnostic -UserProfile 'C:\Users\User').Status | Should -Be Skipped
        $profilePath = 'C:\Users\Andr' + [char]0xe9
        Mock Get-DotfilesDiagnosticEnvironmentValue { 'private-home' }
        Mock Get-DotfilesUserHomeAliasPreflight { [pscustomobject]@{Action='Skip';Message='private-home'} }
        (Get-DotfilesHomeDiagnostic -UserProfile $profilePath -AliasName andre).Status | Should -Be Passed
        Mock Get-DotfilesUserHomeAliasPreflight { [pscustomobject]@{Action='RunNonElevated'} }
        (Get-DotfilesHomeDiagnostic -UserProfile $profilePath -AliasName andre).Status | Should -Be Drift
        Mock Get-DotfilesUserHomeAliasPreflight { [pscustomobject]@{Action='Fail';Message='private-home'} }
        $result = Get-DotfilesHomeDiagnostic -UserProfile $profilePath -AliasName andre
        $result.Status | Should -Be Unknown
        $result.Message | Should -Not -Match 'private-home'
    }
}
