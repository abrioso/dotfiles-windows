Describe 'Portable profile stubs' {
    BeforeAll {
        $path = Join-Path (Split-Path -Parent $PSScriptRoot) 'setup-modules/Install-LocalPowerShellProfiles.ps1'
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$null)
        $assignment = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -eq '$stubContent' }, $true)
        $buildStub = [scriptblock]::Create($assignment.Extent.Text)
    }
    It 'loads each machines local profile from the same synchronized stub' {
        $previous = $env:LOCALAPPDATA
        try {
            $stubMarker = '# test marker'
            $profileFile = [pscustomobject]@{ Name = 'Microsoft.PowerShell_profile.ps1' }
            $localStore = Join-Path $TestDrive 'original-machine'
            . $buildStub
            foreach ($machine in @('André', 'different-user')) {
                $env:LOCALAPPDATA = Join-Path $TestDrive $machine
                $folder = Join-Path $env:LOCALAPPDATA 'dotfiles/powershell-profiles'
                New-Item -ItemType Directory -Path $folder -Force | Out-Null
                Set-Content (Join-Path $folder $profileFile.Name) ("`$script:loadedMachine = `"$machine`"")
                $script:loadedMachine = $null
                . ([scriptblock]::Create($stubContent))
                $script:loadedMachine | Should -Be $machine
            }
            $env:LOCALAPPDATA = Join-Path $TestDrive 'unconfigured-machine'
            { . ([scriptblock]::Create($stubContent)) } | Should -Not -Throw
        } finally { $env:LOCALAPPDATA = $previous }
    }
}
