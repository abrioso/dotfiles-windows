Describe 'Dotfiles update helpers' {
    BeforeAll {
        . "$PSScriptRoot/../setup-scripts/update-functions.ps1"

        function New-UpdateTestDirectory {
            $path = Join-Path $env:TEMP ([System.Guid]::NewGuid())
            New-Item -ItemType Directory -Path $path | Out-Null
            return $path
        }

        function Invoke-UpdateTestGit {
            param(
                [Parameter(Mandatory)][string]$WorkingDirectory,
                [Parameter(ValueFromRemainingArguments)][string[]]$Arguments
            )

            & git -C $WorkingDirectory @Arguments 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "Git command failed in '$WorkingDirectory': git $($Arguments -join ' ')"
            }
        }

        function Initialize-UpdateTestRepository {
            param([Parameter(Mandatory)][string]$RepositoryRoot)

            Invoke-UpdateTestGit -WorkingDirectory $RepositoryRoot init -b main
            Invoke-UpdateTestGit -WorkingDirectory $RepositoryRoot config user.name Test
            Invoke-UpdateTestGit -WorkingDirectory $RepositoryRoot config user.email test@example.invalid
            $configDirectory = Join-Path $RepositoryRoot 'dotfiles-configurations'
            foreach ($template in (Get-ChildItem -LiteralPath $configDirectory -Filter '*.json.example' -File)) {
                Invoke-UpdateTestGit -WorkingDirectory $RepositoryRoot add ("dotfiles-configurations/{0}" -f $template.Name)
            }
            Invoke-UpdateTestGit -WorkingDirectory $RepositoryRoot commit -m templates
        }
    }

    Context 'Get-DotfilesConfigurationTemplate' {
        It 'discovers every JSON example and recommends only shared catalogs' {
            $root = New-UpdateTestDirectory
            try {
                @(
                    'dotfiles-bootstrap-variables.json.example',
                    'env-variables.json.example',
                    'git-variables.json.example',
                    'setup-modules.json.example',
                    'windows-capabilities.json.example',
                    'windows-features.json.example',
                    'winget-packages.json.example',
                    'windows-terminal-settings.json.example'
                ) | ForEach-Object {
                    Set-Content -LiteralPath (Join-Path $root $_) -Value '{}' -Encoding UTF8
                }
                $allowedNames = @(
                    'dotfiles-bootstrap-variables.json',
                    'env-variables.json',
                    'git-variables.json',
                    'setup-modules.json',
                    'windows-capabilities.json',
                    'windows-features.json',
                    'winget-packages.json',
                    'windows-terminal-settings.json'
                )
                $allowed = @($allowedNames | ForEach-Object { Join-Path $root "$_.example" })
                Set-Content -LiteralPath (Join-Path $root 'injected.json.example') -Value '{}' -Encoding UTF8
                Set-Content -LiteralPath (Join-Path $root 'Winget-Packages.json.example') -Value '{}' -Encoding UTF8

                $templates = @(Get-DotfilesConfigurationTemplate -ConfigDirectory $root -AllowedTemplatePath $allowed)
                $names = @($templates.Name)
                $recommended = @($templates | Where-Object Recommended | ForEach-Object Name)

                if (($names -join ',') -ne 'dotfiles-bootstrap-variables.json,env-variables.json,git-variables.json,setup-modules.json,windows-capabilities.json,windows-features.json,windows-terminal-settings.json,winget-packages.json') {
                    throw "Unexpected template discovery order: '$($names -join ',')'."
                }
                if (($recommended -join ',') -ne 'setup-modules.json,windows-capabilities.json,windows-features.json,winget-packages.json') {
                    throw "Unexpected recommended templates: '$($recommended -join ',')'."
                }
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force
            }
        }
        It 'does not authorize a top-level template from a tracked nested path with the same leaf name' {
            $root = New-UpdateTestDirectory
            try {
                $nested = Join-Path $root 'nested'
                New-Item -ItemType Directory -Path $nested | Out-Null
                $topLevel = Join-Path $root 'winget-packages.json.example'
                $nestedTemplate = Join-Path $nested 'winget-packages.json.example'
                Set-Content -LiteralPath $topLevel -Value '{}' -Encoding UTF8
                Set-Content -LiteralPath $nestedTemplate -Value '{}' -Encoding UTF8

                $templates = @(Get-DotfilesConfigurationTemplate -ConfigDirectory $root -AllowedTemplatePath @($nestedTemplate))
                if ($templates.Count -ne 0) {
                    throw 'Tracked provenance must bind to the exact template path, not only its leaf filename.'
                }
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force
            }
        }
    }

    Context 'Updater path boundaries' {
        It 'accepts the repository config directory and rejects backups inside the checkout' {
            $root = New-UpdateTestDirectory
            try {
                $repository = Join-Path $root 'repository'
                $config = Join-Path $repository 'dotfiles-configurations'
                New-Item -ItemType Directory -Path $config -Force | Out-Null

                Assert-DotfilesUpdaterPathBoundary -RepositoryRoot $repository -ConfigDirectory $config -BackupDirectory (Join-Path $root 'backups')

                $threw = $false
                try {
                    Assert-DotfilesUpdaterPathBoundary -RepositoryRoot $repository -ConfigDirectory $config -BackupDirectory (Join-Path $repository 'backups')
                }
                catch {
                    $threw = $true
                }
                if (-not $threw) {
                    throw 'Backup directories inside the repository must be rejected.'
                }
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force
            }
        }
        It 'rejects forward-slash Windows device namespace aliases' {
            $threw = $false
            try {
                Get-DotfilesCanonicalPath -Path '//?/C:/repository' | Out-Null
            }
            catch {
                $threw = $true
            }
            if (-not $threw) {
                throw 'Forward-slash device namespace paths must be rejected before canonicalization.'
            }
        }

        It 'fails closed when a path component cannot be inspected' {
            Mock Get-Item { throw [System.UnauthorizedAccessException]::new('denied') }
            $threw = $false
            try {
                Assert-DotfilesPathHasNoReparsePoint -Path (Join-Path $env:TEMP 'uninspectable-path')
            }
            catch {
                $threw = $true
            }
            if (-not $threw) {
                throw 'Path inspection errors other than a missing item must fail closed.'
            }
        }
    }

    Context 'update.ps1 repository update' {
        It 'fast-forwards the current branch without applying configuration' {
            $root = New-UpdateTestDirectory
            try {
                $remote = Join-Path $root 'remote.git'
                $seed = Join-Path $root 'seed'
                $checkout = Join-Path $root 'checkout'
                New-Item -ItemType Directory -Path $remote, $seed | Out-Null
                $seedConfig = Join-Path $seed 'dotfiles-configurations'
                New-Item -ItemType Directory -Path $seedConfig | Out-Null
                Invoke-UpdateTestGit -WorkingDirectory $remote init --bare
                Invoke-UpdateTestGit -WorkingDirectory $seed init -b main
                Invoke-UpdateTestGit -WorkingDirectory $seed config user.name Test
                Invoke-UpdateTestGit -WorkingDirectory $seed config user.email test@example.invalid
                Set-Content -LiteralPath (Join-Path $seed 'version.txt') -Value 'one' -Encoding UTF8
                Set-Content -LiteralPath (Join-Path $seedConfig 'setup-modules.json.example') -Value '{}' -Encoding UTF8
                Invoke-UpdateTestGit -WorkingDirectory $seed add version.txt dotfiles-configurations/setup-modules.json.example
                Invoke-UpdateTestGit -WorkingDirectory $seed commit -m initial
                Invoke-UpdateTestGit -WorkingDirectory $seed remote add origin $remote
                Invoke-UpdateTestGit -WorkingDirectory $seed push -u origin main
                & git clone --branch main $remote $checkout 2>&1 | Out-Null
                if ($LASTEXITCODE -ne 0) { throw 'Failed to create updater test clone.' }

                Set-Content -LiteralPath (Join-Path $seed 'version.txt') -Value 'two' -Encoding UTF8
                Invoke-UpdateTestGit -WorkingDirectory $seed add version.txt
                Invoke-UpdateTestGit -WorkingDirectory $seed commit -m update
                Invoke-UpdateTestGit -WorkingDirectory $seed push origin main
                $config = Join-Path $checkout 'dotfiles-configurations'

                $windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
                $updateScript = "$PSScriptRoot/../setup-scripts/update.ps1"
                & $windowsPowerShell -NoProfile -ExecutionPolicy Bypass -File $updateScript `
                    -NonInteractive -UpdateRepository -RepositoryRoot $checkout `
                    -ConfigDirectory $config -BackupDirectory (Join-Path $root 'backups')
                if ($LASTEXITCODE -ne 0) {
                    throw "Expected update.ps1 to succeed under Windows PowerShell 5.1, got exit code $LASTEXITCODE."
                }

                $version = (Get-Content -LiteralPath (Join-Path $checkout 'version.txt') -Raw).Trim()
                if ($version -ne 'two') {
                    throw "Expected the checkout to fast-forward to version two, got '$version'."
                }
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force
            }
        }

        It 'fails when Git fetch returns a non-zero exit code under Windows PowerShell 5.1' {
            $root = New-UpdateTestDirectory
            try {
                $repository = Join-Path $root 'repository'
                $config = Join-Path $repository 'dotfiles-configurations'
                New-Item -ItemType Directory -Path $config -Force | Out-Null
                Set-Content -LiteralPath (Join-Path $config 'setup-modules.json.example') -Value '{}' -Encoding UTF8
                Initialize-UpdateTestRepository -RepositoryRoot $repository
                Invoke-UpdateTestGit -WorkingDirectory $repository remote add origin (Join-Path $root 'missing-remote.git')

                $windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
                $updateScript = "$PSScriptRoot/../setup-scripts/update.ps1"
                & $windowsPowerShell -NoProfile -ExecutionPolicy Bypass -File $updateScript `
                    -NonInteractive -UpdateRepository -RepositoryRoot $repository `
                    -ConfigDirectory $config -BackupDirectory (Join-Path $root 'backups')

                if ($LASTEXITCODE -eq 0) {
                    throw 'Expected update.ps1 to fail when Git fetch returns a non-zero exit code.'
                }
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force
            }
        }
    }

    Context 'update.ps1 non-interactive selection' {
        It 'derives the configuration directory from an overridden repository root' {
            $root = New-UpdateTestDirectory
            try {
                $repository = Join-Path $root 'repository'
                $config = Join-Path $repository 'dotfiles-configurations'
                New-Item -ItemType Directory -Path $config -Force | Out-Null
                Set-Content -LiteralPath (Join-Path $config 'winget-packages.json.example') -Value '{"source":"tracked"}' -Encoding UTF8
                Initialize-UpdateTestRepository -RepositoryRoot $repository

                & "$PSScriptRoot/../setup-scripts/update.ps1" -NonInteractive -SkipRepositoryUpdate -RepositoryRoot $repository -BackupDirectory (Join-Path $root 'backups')
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force
            }
        }

        It 'rejects a modified template even when Git marks it assume-unchanged' {
            $root = New-UpdateTestDirectory
            try {
                $repository = Join-Path $root 'repository'
                $config = Join-Path $repository 'dotfiles-configurations'
                $backups = Join-Path $root 'backups'
                New-Item -ItemType Directory -Path $config -Force | Out-Null
                $template = Join-Path $config 'winget-packages.json.example'
                $target = Join-Path $config 'winget-packages.json'
                Set-Content -LiteralPath $template -Value '{"source":"tracked"}' -Encoding UTF8
                Set-Content -LiteralPath $target -Value '{"source":"local"}' -Encoding UTF8
                Initialize-UpdateTestRepository -RepositoryRoot $repository
                Invoke-UpdateTestGit -WorkingDirectory $repository update-index --assume-unchanged dotfiles-configurations/winget-packages.json.example
                Set-Content -LiteralPath $template -Value '{"source":"hidden-modification"}' -Encoding UTF8

                $threw = $false
                try {
                    & "$PSScriptRoot/../setup-scripts/update.ps1" -NonInteractive -SkipRepositoryUpdate -TemplateName 'winget-packages.json' -RepositoryRoot $repository -ConfigDirectory $config -BackupDirectory $backups
                }
                catch {
                    $threw = $true
                }

                $local = Get-Content -LiteralPath $target -Raw | ConvertFrom-Json
                if (-not $threw -or $local.source -ne 'local' -or (Test-Path -LiteralPath $backups)) {
                    throw 'Working template content must match the tracked Git object regardless of index flags.'
                }
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force
            }
        }

        It 'validates every selected template before changing any local JSON' {
            $root = New-UpdateTestDirectory
            try {
                $repository = Join-Path $root 'repository'
                $config = Join-Path $repository 'dotfiles-configurations'
                $backups = Join-Path $root 'backups'
                New-Item -ItemType Directory -Path $config -Force | Out-Null
                Set-Content -LiteralPath (Join-Path $config 'setup-modules.json.example') -Value '{"source":"new-modules"}' -Encoding UTF8
                Set-Content -LiteralPath (Join-Path $config 'setup-modules.json') -Value '{"source":"local-modules"}' -Encoding UTF8
                Set-Content -LiteralPath (Join-Path $config 'winget-packages.json.example') -Value '{invalid' -Encoding UTF8
                Set-Content -LiteralPath (Join-Path $config 'winget-packages.json') -Value '{"source":"local-winget"}' -Encoding UTF8
                Initialize-UpdateTestRepository -RepositoryRoot $repository

                $threw = $false
                try {
                    & "$PSScriptRoot/../setup-scripts/update.ps1" -NonInteractive -SkipRepositoryUpdate -TemplateName 'setup-modules.json','winget-packages.json' -RepositoryRoot $repository -ConfigDirectory $config -BackupDirectory $backups
                }
                catch {
                    $threw = $true
                }

                $modules = Get-Content -LiteralPath (Join-Path $config 'setup-modules.json') -Raw | ConvertFrom-Json
                if (-not $threw -or $modules.source -ne 'local-modules' -or (Test-Path -LiteralPath $backups)) {
                    throw 'All selected templates must validate before the first replacement occurs.'
                }
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force
            }
        }

        It 'rolls back earlier replacements when a later replacement fails' {
            $root = New-UpdateTestDirectory
            try {
                $repository = Join-Path $root 'repository'
                $config = Join-Path $repository 'dotfiles-configurations'
                $backups = Join-Path $root 'backups'
                New-Item -ItemType Directory -Path $config -Force | Out-Null
                Set-Content -LiteralPath (Join-Path $config 'setup-modules.json.example') -Value '{"source":"new-modules"}' -Encoding UTF8
                Set-Content -LiteralPath (Join-Path $config 'setup-modules.json') -Value '{"source":"local-modules"}' -Encoding UTF8
                Set-Content -LiteralPath (Join-Path $config 'winget-packages.json.example') -Value '{"source":"new-winget"}' -Encoding UTF8
                Initialize-UpdateTestRepository -RepositoryRoot $repository
                New-Item -ItemType Directory -Path (Join-Path $config 'winget-packages.json') | Out-Null

                $threw = $false
                try {
                    & "$PSScriptRoot/../setup-scripts/update.ps1" -NonInteractive -SkipRepositoryUpdate -TemplateName 'setup-modules.json','winget-packages.json' -RepositoryRoot $repository -ConfigDirectory $config -BackupDirectory $backups
                }
                catch {
                    $threw = $true
                }

                $modules = Get-Content -LiteralPath (Join-Path $config 'setup-modules.json') -Raw | ConvertFrom-Json
                if (-not $threw -or $modules.source -ne 'local-modules') {
                    throw 'A failed batch must restore every earlier local JSON replacement.'
                }
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force
            }
        }

        It 'replaces only explicitly selected local JSON files' {
            $root = New-UpdateTestDirectory
            try {
                $repository = Join-Path $root 'repository'
                $config = Join-Path $repository 'dotfiles-configurations'
                $backups = Join-Path $root 'backups'
                New-Item -ItemType Directory -Path $config -Force | Out-Null
                Set-Content -LiteralPath (Join-Path $config 'winget-packages.json.example') -Value '{"source":"new-winget"}' -Encoding UTF8
                Set-Content -LiteralPath (Join-Path $config 'winget-packages.json') -Value '{"source":"local-winget"}' -Encoding UTF8
                Set-Content -LiteralPath (Join-Path $config 'windows-features.json.example') -Value '{"source":"new-features"}' -Encoding UTF8
                Set-Content -LiteralPath (Join-Path $config 'windows-features.json') -Value '{"source":"local-features"}' -Encoding UTF8
                Initialize-UpdateTestRepository -RepositoryRoot $repository

                & "$PSScriptRoot/../setup-scripts/update.ps1" -NonInteractive -SkipRepositoryUpdate -TemplateName 'winget-packages.json' -RepositoryRoot $repository -ConfigDirectory $config -BackupDirectory $backups

                $winget = Get-Content -LiteralPath (Join-Path $config 'winget-packages.json') -Raw | ConvertFrom-Json
                $features = Get-Content -LiteralPath (Join-Path $config 'windows-features.json') -Raw | ConvertFrom-Json
                if ($winget.source -ne 'new-winget' -or $features.source -ne 'local-features') {
                    throw 'The updater must replace only the explicitly selected local JSON files.'
                }
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force
            }
        }
    }

    Context 'Update-DotfilesConfigurationTemplate' {
        It 'backs up an existing local JSON before replacing it' {
            $root = New-UpdateTestDirectory
            try {
                $template = Join-Path $root 'winget-packages.json.example'
                $target = Join-Path $root 'winget-packages.json'
                $backupRoot = Join-Path $root 'backups'
                Set-Content -LiteralPath $template -Value '{"version":"new"}' -Encoding UTF8
                Set-Content -LiteralPath $target -Value '{"version":"local"}' -Encoding UTF8

                $result = Update-DotfilesConfigurationTemplate -TemplatePath $template -TargetPath $target -BackupDirectory $backupRoot

                $updated = Get-Content -LiteralPath $target -Raw | ConvertFrom-Json
                $backup = Get-Content -LiteralPath $result.BackupPath -Raw | ConvertFrom-Json
                if ($result.Status -ne 'Replaced' -or $updated.version -ne 'new' -or $backup.version -ne 'local') {
                    throw 'Expected an atomic replacement with the previous local JSON preserved in a backup.'
                }
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force
            }
        }

        It 'does not create a backup when template and local JSON are identical' {
            $root = New-UpdateTestDirectory
            try {
                $template = Join-Path $root 'windows-features.json.example'
                $target = Join-Path $root 'windows-features.json'
                $backupRoot = Join-Path $root 'backups'
                Set-Content -LiteralPath $template -Value '{"wsl":["VirtualMachinePlatform"]}' -Encoding UTF8
                Copy-Item -LiteralPath $template -Destination $target

                $result = Update-DotfilesConfigurationTemplate -TemplatePath $template -TargetPath $target -BackupDirectory $backupRoot

                if ($result.Status -ne 'Unchanged' -or $result.BackupPath -or (Test-Path -LiteralPath $backupRoot)) {
                    throw 'Identical JSON must remain unchanged without generating a backup.'
                }
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force
            }
        }

        It 'creates a missing local JSON without a backup' {
            $root = New-UpdateTestDirectory
            try {
                $template = Join-Path $root 'setup-modules.json.example'
                $target = Join-Path $root 'setup-modules.json'
                $backupRoot = Join-Path $root 'backups'
                Set-Content -LiteralPath $template -Value '{"packages":[]}' -Encoding UTF8

                $result = Update-DotfilesConfigurationTemplate -TemplatePath $template -TargetPath $target -BackupDirectory $backupRoot

                if ($result.Status -ne 'Created' -or $result.BackupPath -or -not (Test-Path -LiteralPath $target)) {
                    throw 'A missing local JSON must be created directly from its selected template.'
                }
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force
            }
        }

        It 'rejects invalid template JSON without changing the local file' {
            $root = New-UpdateTestDirectory
            try {
                $template = Join-Path $root 'winget-packages.json.example'
                $target = Join-Path $root 'winget-packages.json'
                $backupRoot = Join-Path $root 'backups'
                Set-Content -LiteralPath $template -Value '{invalid' -Encoding UTF8
                Set-Content -LiteralPath $target -Value '{"preserve":true}' -Encoding UTF8

                $threw = $false
                try {
                    Update-DotfilesConfigurationTemplate -TemplatePath $template -TargetPath $target -BackupDirectory $backupRoot | Out-Null
                }
                catch {
                    $threw = $true
                }

                $local = Get-Content -LiteralPath $target -Raw | ConvertFrom-Json
                if (-not $threw -or -not $local.preserve -or (Test-Path -LiteralPath $backupRoot)) {
                    throw 'Invalid template JSON must fail before backup or replacement.'
                }
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force
            }
        }
    }
}
