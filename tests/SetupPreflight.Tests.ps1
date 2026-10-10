Describe 'Setup configuration preflight' {
    BeforeAll {
        $repositoryRoot = Split-Path -Parent $PSScriptRoot
        . "$repositoryRoot/setup-scripts/setup-functions.ps1"
        $moduleDirectory = Join-Path $repositoryRoot 'setup-modules'
        function Save-PreflightFixture {
            param([string]$Name, $Value)
            $Value | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $configDirectory "$Name.json") -Encoding UTF8
        }
        function Invoke-PreflightFixture {
            Assert-DotfilesSetupConfiguration -DotfilesVariables $bootstrap -ConfigDirectory $configDirectory -ModuleDirectory $moduleDirectory
        }
    }
    BeforeEach {
        $configDirectory = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $configDirectory | Out-Null
        foreach ($file in Get-ChildItem "$repositoryRoot/dotfiles-configurations/*.json.example") {
            Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $configDirectory ($file.Name -replace '\.example$', ''))
        }
        $bootstrap = Read-DotfilesConfigurationObject (Join-Path $configDirectory 'dotfiles-bootstrap-variables.json')
    }
    It 'accepts the tracked defaults' {
        { Invoke-PreflightFixture } | Should -Not -Throw
    }
    It 'preserves explicit empty selections' {
        foreach ($selector in @('INSTALL_FEATURES', 'INSTALL_CAPABILITIES', 'INSTALL_PACKAGES', 'INSTALL_SETTINGS')) {
            $bootstrap.$selector = @()
        }
        { Invoke-PreflightFixture } | Should -Not -Throw
        @(Get-DotfilesSetupPlan -DotfilesVariables $bootstrap -ConfigDirectory $configDirectory) | Should -HaveCount 0
    }
    It 'preserves missing selectors and legacy string selectors and package IDs' {
        foreach ($selector in @('INSTALL_FEATURES', 'INSTALL_CAPABILITIES', 'INSTALL_PACKAGES', 'INSTALL_SETTINGS')) {
            $bootstrap.PSObject.Properties.Remove($selector)
        }
        { Invoke-PreflightFixture } | Should -Not -Throw
        $bootstrap | Add-Member INSTALL_PACKAGES 'base'
        $bootstrap | Add-Member INSTALL_SETTINGS 'base'
        Save-PreflightFixture winget-packages ([pscustomobject]@{base=@('Git.Git')})
        # Keep a minimal legacy catalog with package ID strings and a single selector.
        $setupConfig = [pscustomobject]@{settings=[pscustomobject]@{base=@([pscustomobject]@{script='Apply-GitConfig.ps1';requiresPackageGroups=@('base')})}}
        Save-PreflightFixture setup-modules $setupConfig
        { Invoke-PreflightFixture } | Should -Not -Throw
    }
    It 'rejects unknown <Selector> selections with available choices' -ForEach @(
        @{Selector='INSTALL_PACKAGES'}, @{Selector='INSTALL_SETTINGS'},
        @{Selector='INSTALL_FEATURES'}, @{Selector='INSTALL_CAPABILITIES'}
    ) {
        $bootstrap.$Selector = @('typo')
        { Invoke-PreflightFixture } | Should -Throw "*Unknown selection 'typo' in $Selector*Available values*"
    }
    It 'rejects invalid selector types: <Label>' -ForEach @(
        @{Label='null';Value=$null}, @{Label='boolean';Value=$false},
        @{Label='number';Value=3}, @{Label='object';Value=[pscustomobject]@{base=$true}},
        @{Label='empty string';Value=''}, @{Label='mixed array';Value=@('base',1)}
    ) {
        $bootstrap.INSTALL_PACKAGES = $Value
        { Invoke-PreflightFixture } | Should -Throw '*INSTALL_PACKAGES*'
    }
    It 'rejects missing required bootstrap values' {
        $bootstrap.WORKSPACE_FOLDER = ''
        { Invoke-PreflightFixture } | Should -Throw '*WORKSPACE_FOLDER*'
    }
    It 'rejects unsupported repository endpoints before Git runs' {
        $bootstrap.REPOSITORY_ENDPOINT_TYPE = 'typo'
        { Invoke-PreflightFixture } | Should -Throw '*Unsupported REPOSITORY_ENDPOINT_TYPE*'
    }
    It 'rejects missing files' {
        Remove-Item -LiteralPath (Join-Path $configDirectory 'winget-packages.json')
        { Invoke-PreflightFixture } | Should -Throw '*Required configuration file not found: winget-packages.json*'
    }
    It 'rejects malformed JSON without including private values in the error' {
        '{"private":"fixture-sensitive-value"' | Set-Content (Join-Path $configDirectory 'git-variables.json')
        try { Invoke-PreflightFixture; throw 'Expected preflight rejection.' }
        catch {
            $_.Exception.Message | Should -Match 'Cannot read valid JSON from git-variables.json'
            $_.Exception.Message | Should -Not -Match 'fixture-sensitive-value'
        }
    }
    It 'rejects non-object JSON roots: <Json>' -ForEach @(
        @{Json='[]'}, @{Json='[{}]'}, @{Json='null'}, @{Json='true'}, @{Json='"text"'}
    ) {
        $Json | Set-Content (Join-Path $configDirectory 'winget-packages.json')
        { Invoke-PreflightFixture } | Should -Throw '*must contain a JSON object*'
    }
    It 'rejects misspelled bootstrap selector names' {
        $bootstrap | Add-Member INSTALL_PACKAGE @('base')
        { Invoke-PreflightFixture } | Should -Throw "*Unknown bootstrap selector 'INSTALL_PACKAGE'*"
    }
    It 'rejects misspelled module section names' {
        Save-PreflightFixture setup-modules ([pscustomobject]@{setting=[pscustomobject]@{}})
        { Invoke-PreflightFixture } | Should -Throw "*Unknown setup-modules.json section 'setting'*"
    }
    It 'rejects malformed package declarations: <Label>' -ForEach @(
        @{Label='group object';Value=[pscustomobject]@{id='Git.Git'}},
        @{Label='missing ID';Value=@([pscustomobject]@{scope='user'})},
        @{Label='invalid ID';Value=@('Git.Git --scope machine')},
        @{Label='invalid scope';Value=@([pscustomobject]@{id='Git.Git';scope='invalid'})},
        @{Label='invalid installer';Value=@([pscustomobject]@{id='Git.Git';installerType='invalid'})}
    ) {
        Save-PreflightFixture winget-packages ([pscustomobject]@{base=$Value})
        { Invoke-PreflightFixture } | Should -Throw '*winget-packages.json.base*'
    }
    It 'rejects non-array feature groups' {
        Save-PreflightFixture windows-features ([pscustomobject]@{wsl=$false})
        { Invoke-PreflightFixture } | Should -Throw '*windows-features.json.wsl*'
    }
    It 'rejects missing module scripts even in unselected groups' {
        Save-PreflightFixture setup-modules ([pscustomobject]@{settings=[pscustomobject]@{base=@([pscustomobject]@{script='Missing.ps1'})}})
        $bootstrap.INSTALL_SETTINGS = @()
        { Invoke-PreflightFixture } | Should -Throw '*Setup module script not found: Missing.ps1*'
    }
    It 'rejects module paths outside the module directory' {
        Save-PreflightFixture setup-modules ([pscustomobject]@{settings=[pscustomobject]@{base=@([pscustomobject]@{script='../setup-scripts/setup.ps1'})}})
        $bootstrap.INSTALL_SETTINGS = @()
        { Invoke-PreflightFixture } | Should -Throw '*without directory components*'
    }
    It 'requires JSON booleans for elevation flags' {
        Save-PreflightFixture setup-modules ([pscustomobject]@{settings=[pscustomobject]@{base=@([pscustomobject]@{script='Apply-GitConfig.ps1';requiresAdmin='false'})}})
        $bootstrap.INSTALL_SETTINGS = @()
        { Invoke-PreflightFixture } | Should -Throw '*requiresAdmin must be a JSON boolean*'
    }
    It 'rejects invalid module selectors' {
        Save-PreflightFixture setup-modules ([pscustomobject]@{packages=@([pscustomobject]@{script='Install-WingetPackages.ps1';whenSelected=@('typo')})})
        $bootstrap.INSTALL_SETTINGS = @()
        { Invoke-PreflightFixture } | Should -Throw '*whenSelected*Available values*'
    }
    It 'rejects selected settings whose package dependencies are missing' {
        $bootstrap.INSTALL_PACKAGES = @('base')
        { Invoke-PreflightFixture } | Should -Throw '*missing package group*'
    }
    It 'rejects invalid environment entries' {
        Save-PreflightFixture env-variables ([pscustomobject]@{EnvironmentVariables=@([pscustomobject]@{Name='X';Value='value';Scope='Process'})})
        { Invoke-PreflightFixture } | Should -Throw '*User/Machine Scope*'
    }
    It 'rejects structured Git values before Git configuration is applied' {
        Save-PreflightFixture git-variables ([pscustomobject]@{'user.name'=@('name','other')})
        { Invoke-PreflightFixture } | Should -Throw '*scalar, non-null values*'
    }
    It 'validates saved configuration after synchronization without overwriting it' {
        $sourceRoot = Join-Path $TestDrive 'transport'
        New-Item -ItemType Directory -Path "$sourceRoot/dotfiles-configurations" -Force | Out-Null
        $bootstrap.INSTALL_PACKAGES = @('bsae')
        Save-PreflightFixture dotfiles-bootstrap-variables $bootstrap
        $savedPath = Join-Path $configDirectory 'dotfiles-bootstrap-variables.json'
        $savedBytes = [IO.File]::ReadAllText($savedPath)
        Copy-Item "$repositoryRoot/dotfiles-configurations/dotfiles-bootstrap-variables.json.example" "$sourceRoot/dotfiles-configurations/dotfiles-bootstrap-variables.json"
        $setupAst = [System.Management.Automation.Language.Parser]::ParseFile("$repositoryRoot/setup-scripts/setup.ps1", [ref]$null, [ref]$null)
        $sync = $setupAst.Find({param($node) $node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Sync-DotfilesLocalConfiguration'}, $true)
        $reload = $setupAst.Find({param($node) $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -eq '$DotfilesVariables' -and $node.Right.Extent.Text -like '*Read-DotfilesConfigurationObject*'}, $true)
        $assertion = @($setupAst.FindAll({param($node) $node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Assert-DotfilesSetupConfiguration'}, $true))[-1]
        $reload.Extent.StartOffset | Should -BeGreaterThan $sync.Extent.EndOffset
        $assertion.Extent.StartOffset | Should -BeGreaterThan $reload.Extent.EndOffset
        $dotfileRootDir = $sourceRoot
        # The fixture directory is not named dotfiles-configurations; use explicit target paths.
        $handoff = [scriptblock]::Create($reload.Extent.Text + "`n" + $assertion.Extent.Text)
        $dotfilesDirectory = Join-Path $TestDrive 'persistent'
        New-Item -ItemType Directory -Path $dotfilesDirectory -Force | Out-Null
        Copy-Item -LiteralPath $configDirectory -Destination "$dotfilesDirectory/dotfiles-configurations" -Recurse
        Sync-DotfilesLocalConfiguration -SourceRoot $dotfileRootDir -TargetRoot $dotfilesDirectory
        $moduleConfigDirectory = "$dotfilesDirectory/dotfiles-configurations"
        $moduleScriptsPath = $moduleDirectory
        { . $handoff } | Should -Throw "*Unknown selection 'bsae'*"
        [IO.File]::ReadAllText("$moduleConfigDirectory/dotfiles-bootstrap-variables.json") | Should -BeExactly $savedBytes
    }
    It 'stops invalid setup before prerequisite installation in <HostName>' -ForEach @(
        @{HostName='PowerShell 7';HostCommand='pwsh'},
        @{HostName='Windows PowerShell 5.1';HostCommand='powershell'}
    ) {
        $hostExecutable = (Get-Command $HostCommand -ErrorAction Stop).Source
        $fixtureRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path "$fixtureRoot/setup-scripts" -Force | Out-Null
        Copy-Item -LiteralPath $configDirectory -Destination "$fixtureRoot/dotfiles-configurations" -Recurse
        Copy-Item -LiteralPath $moduleDirectory -Destination "$fixtureRoot/setup-modules" -Recurse
        Copy-Item "$repositoryRoot/setup-scripts/setup.ps1", "$repositoryRoot/setup-scripts/setup-functions.ps1", "$repositoryRoot/setup-scripts/configure.ps1" "$fixtureRoot/setup-scripts"
        @'
function Start-Logging { param($LogFilePath, [switch]$PassThru, [switch]$Append) return $LogFilePath }
function Complete-DotfilesSetupLogging { param($LogFilePath, $DotfilesDirectory) return $LogFilePath }
function Stop-Logging { }
function Install-DotfilesPrerequisites {
    [IO.File]::WriteAllText((Join-Path (Split-Path -Parent $PSScriptRoot) 'prerequisites-reached.txt'), 'reached')
    return $false
}
'@ | Add-Content "$fixtureRoot/setup-scripts/setup-functions.ps1"
        $fixtureBootstrapPath = "$fixtureRoot/dotfiles-configurations/dotfiles-bootstrap-variables.json"
        $invalidBootstrap = Read-DotfilesConfigurationObject $fixtureBootstrapPath
        $invalidBootstrap.INSTALL_PACKAGES = @('bsae')
        $invalidBootstrap | ConvertTo-Json -Depth 20 | Set-Content $fixtureBootstrapPath
        $output = & $hostExecutable -NoProfile -File "$fixtureRoot/setup-scripts/setup.ps1" -NonInteractive 2>&1
        $LASTEXITCODE | Should -Be 1
        ($output -join "`n") | Should -Match "Unknown selection 'bsae'"
        Test-Path "$fixtureRoot/prerequisites-reached.txt" | Should -BeFalse
        # A valid control must reach the sentinel; no real prerequisite installation is run.
        $bootstrap | ConvertTo-Json -Depth 20 | Set-Content $fixtureBootstrapPath
        $null = & $hostExecutable -NoProfile -File "$fixtureRoot/setup-scripts/setup.ps1" -NonInteractive 2>&1
        Test-Path "$fixtureRoot/prerequisites-reached.txt" | Should -BeTrue
    }
}
