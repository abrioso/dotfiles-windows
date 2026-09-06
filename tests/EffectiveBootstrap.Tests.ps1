Describe 'Persistent bootstrap choices' {
    BeforeAll {
        $root = Split-Path -Parent $PSScriptRoot
        . "$root/setup-scripts/setup-functions.ps1"
        $setupAst = [System.Management.Automation.Language.Parser]::ParseFile("$root/setup-scripts/setup.ps1", [ref]$null, [ref]$null)
        # Execute the real synchronization/reload statements without installing prerequisites.
        $sync = $setupAst.Find({ param($node) $node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Sync-DotfilesLocalConfiguration' }, $true)
        $reload = $setupAst.Find({ param($node) $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -eq '$DotfilesVariables' -and $node.Right.Extent.Text -like '*Read-DotfilesJsonFile*' }, $true)
        if (-not $reload -or $reload.Extent.StartOffset -lt $sync.Extent.EndOffset) { throw 'Persistent choices must be loaded after synchronization.' }
        $handoff = [scriptblock]::Create($sync.Extent.Text + "`n" + $reload.Extent.Text)
        $catalog = "$root/dotfiles-configurations/setup-modules.json.example"
    }
    It 'uses saved opt-outs for the plan and preserves saved branch bytes' {
        $dotfileRootDir = Join-Path $TestDrive 'transport'
        $dotfilesDirectory = Join-Path $TestDrive 'clone'
        foreach ($dir in @($dotfileRootDir, $dotfilesDirectory)) {
            New-Item -ItemType Directory -Path "$dir/dotfiles-configurations" -Force | Out-Null
        }
        $saved = '{"GITHUB_DOTFILES_BRANCH":"saved-branch","INSTALL_FEATURES":[],"INSTALL_CAPABILITIES":[],"INSTALL_PACKAGES":[],"INSTALL_SETTINGS":[]}'
        $target = "$dotfilesDirectory/dotfiles-configurations/dotfiles-bootstrap-variables.json"
        [IO.File]::WriteAllText($target, $saved)
        $DotfilesVariables = [pscustomobject]@{ INSTALL_FEATURES = @('wsl'); INSTALL_PACKAGES = @('base'); INSTALL_SETTINGS = @('base') }
        $DotfilesVariables | ConvertTo-Json | Set-Content "$dotfileRootDir/dotfiles-configurations/dotfiles-bootstrap-variables.json"
        Copy-Item $catalog "$dotfilesDirectory/dotfiles-configurations/setup-modules.json"
        . $handoff
        $DotfilesVariables.GITHUB_DOTFILES_BRANCH | Should -Be 'saved-branch'
        @(Get-DotfilesSetupPlan -DotfilesVariables $DotfilesVariables -ConfigDirectory "$dotfilesDirectory/dotfiles-configurations") | Should -HaveCount 0
        [IO.File]::ReadAllText($target) | Should -BeExactly $saved
    }
}
