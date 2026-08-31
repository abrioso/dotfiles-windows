Describe 'Bootstrap reliability contracts' {
    BeforeAll {
        $script:repositoryRoot = Split-Path -Parent $PSScriptRoot
        . "$script:repositoryRoot/setup-scripts/setup-functions.ps1"
    }

    Context 'Logging reliability' {
        It 'returns the temporary fallback path when the requested log directory cannot be created' {
            $requestedPath = Join-Path (Join-Path $TestDrive 'blocked') 'setup.txt'
            $script:capturedTranscriptPath = $null
            Mock Test-Path { return $false }
            Mock New-Item { throw [System.UnauthorizedAccessException]::new('denied') }
            Mock Start-Transcript {
                $script:capturedTranscriptPath = $Path
                'Transcript started, output file is representative.txt'
            }

            $actualPath = Start-Logging -LogFilePath $requestedPath -PassThru

            if ($actualPath -isnot [string] -or (Split-Path -Parent $actualPath) -ne $env:TEMP -or $actualPath -ne $script:capturedTranscriptPath) {
                throw 'Start-Logging must emit exactly the actual temporary transcript path.'
            }
        }

        It 'fails closed when an explicitly required transcript path is unavailable' {
            $requestedPath = Join-Path (Join-Path $TestDrive 'blocked') 'module.txt'
            Mock Test-Path { return $false }
            Mock New-Item { throw [System.UnauthorizedAccessException]::new('denied') }
            Mock Start-Transcript { }

            $threw = $false
            try {
                Start-Logging -LogFilePath $requestedPath -PassThru -RequireRequestedPath | Out-Null
            }
            catch {
                $threw = $true
            }
            if (-not $threw) {
                throw 'A required module transcript path must fail closed instead of running without diagnostics.'
            }
            Should -Invoke Start-Transcript -Times 0 -Exactly
        }

        It 'appends a child-process transcript to the parent transcript' {
            $logPath = Join-Path $TestDrive 'cross-process.txt'
            $childPath = Join-Path $TestDrive 'append-child.ps1'
            $functionsPath = Join-Path $script:repositoryRoot 'setup-scripts/setup-functions.ps1'
            @"
. '$functionsPath'
Start-Logging -LogFilePath '$logPath' -Append
Write-Host 'child transcript marker'
Stop-Logging
"@ | Set-Content -LiteralPath $childPath

            Start-Logging -LogFilePath $logPath
            Write-Host 'parent transcript marker'
            Stop-Logging
            & (Join-Path $PSHOME 'pwsh') -NoProfile -File $childPath
            $LASTEXITCODE | Should -Be 0

            $transcript = Get-Content -LiteralPath $logPath -Raw
            $transcript | Should -Match 'parent transcript marker'
            $transcript | Should -Match 'child transcript marker'
        }

        It 'retains a relative requested transcript after the working directory changes' {
            $initialDirectory = Join-Path $TestDrive 'relative-initial'
            $cloneDirectory = Join-Path $TestDrive 'relative-clone'
            New-Item -ItemType Directory -Path (Join-Path $initialDirectory 'logs') -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $cloneDirectory '.git') -Force | Out-Null
            Push-Location $initialDirectory
            $loggingStarted = $false
            try {
                $actualPath = Start-Logging -LogFilePath 'logs/setup-relative.txt' -PassThru
                $loggingStarted = $true
                Write-Host 'relative transcript marker'
                Set-Location $cloneDirectory

                $durablePath = Complete-DotfilesSetupLogging -LogFilePath $actualPath -DotfilesDirectory $cloneDirectory
                $loggingStarted = $false

                [System.IO.Path]::IsPathRooted($actualPath) | Should -BeTrue
                $durablePath | Should -Be (Join-Path $cloneDirectory 'logs/setup-relative.txt')
                Test-Path -LiteralPath $durablePath -PathType Leaf | Should -BeTrue
                Get-Content -LiteralPath $durablePath -Raw | Should -Match 'relative transcript marker'
            }
            finally {
                if ($loggingStarted) {
                    Stop-Logging
                }
                Pop-Location
            }
        }

        It 'returns exactly one path when Stop-Transcript emits success output' {
            $fallbackDirectory = Join-Path $TestDrive 'single-return-fallback'
            $fallbackPath = Join-Path $fallbackDirectory 'setup-single-return.txt'
            New-Item -ItemType Directory -Path $fallbackDirectory | Out-Null
            Set-Content -LiteralPath $fallbackPath -Value 'single return transcript'
            Mock Stop-Transcript { 'Transcript stopped, output file is representative.txt' }

            $output = @(Complete-DotfilesSetupLogging -LogFilePath $fallbackPath -DotfilesDirectory $null)

            $output.Count | Should -Be 1
            $output[0] | Should -Be $fallbackPath
        }

        It 'moves a finalized fallback transcript into persistent clone logs' {
            $fallbackDirectory = Join-Path $TestDrive 'fallback'
            $cloneDirectory = Join-Path $TestDrive 'clone'
            $fallbackPath = Join-Path $fallbackDirectory 'setup-bootstrap.txt'
            New-Item -ItemType Directory -Path $fallbackDirectory, $cloneDirectory | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $cloneDirectory '.git') | Out-Null
            Set-Content -LiteralPath $fallbackPath -Value 'bootstrap transcript'
            Mock Stop-Transcript { }

            $durablePath = Complete-DotfilesSetupLogging -LogFilePath $fallbackPath -DotfilesDirectory $cloneDirectory

            $durablePath | Should -Be (Join-Path $cloneDirectory 'logs/setup-bootstrap.txt')
            Test-Path -LiteralPath $fallbackPath | Should -BeFalse
            Get-Content -LiteralPath $durablePath | Should -Be 'bootstrap transcript'
        }

        It 'retains an early-failure transcript without creating the missing clone' {
            $fallbackDirectory = Join-Path $TestDrive 'local-app-data/dotfiles/logs'
            $missingCloneDirectory = Join-Path $TestDrive 'missing-clone'
            $fallbackPath = Join-Path $fallbackDirectory 'setup-early-failure.txt'
            New-Item -ItemType Directory -Path $fallbackDirectory | Out-Null
            Set-Content -LiteralPath $fallbackPath -Value 'early failure transcript'
            Mock Stop-Transcript { }

            $durablePath = Complete-DotfilesSetupLogging -LogFilePath $fallbackPath -DotfilesDirectory $missingCloneDirectory

            $durablePath | Should -Be $fallbackPath
            Test-Path -LiteralPath $durablePath -PathType Leaf | Should -BeTrue
            Test-Path -LiteralPath $missingCloneDirectory | Should -BeFalse
        }

        It 'retains a fallback transcript when the target directory is not a Git checkout' {
            $fallbackDirectory = Join-Path $TestDrive 'non-repo-fallback'
            $nonRepoDirectory = Join-Path $TestDrive 'partial-clone'
            $fallbackPath = Join-Path $fallbackDirectory 'setup-partial-clone.txt'
            New-Item -ItemType Directory -Path $fallbackDirectory, $nonRepoDirectory | Out-Null
            Set-Content -LiteralPath $fallbackPath -Value 'partial clone transcript'
            Mock Stop-Transcript { }

            $durablePath = Complete-DotfilesSetupLogging -LogFilePath $fallbackPath -DotfilesDirectory $nonRepoDirectory

            $durablePath | Should -Be $fallbackPath
            Test-Path -LiteralPath $fallbackPath -PathType Leaf | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $nonRepoDirectory 'logs') | Should -BeFalse
        }

        It 'reports the durable main transcript after it exists' {
            $fallbackDirectory = Join-Path $TestDrive 'report-fallback'
            $cloneDirectory = Join-Path $TestDrive 'report-clone'
            $fallbackPath = Join-Path $fallbackDirectory 'setup-report.txt'
            New-Item -ItemType Directory -Path $fallbackDirectory, $cloneDirectory | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $cloneDirectory '.git') | Out-Null
            Set-Content -LiteralPath $fallbackPath -Value 'reported transcript'
            Mock Stop-Transcript { }

            $output = @(Complete-DotfilesSetupLogging -LogFilePath $fallbackPath -DotfilesDirectory $cloneDirectory 6>&1)
            $durablePath = Join-Path $cloneDirectory 'logs/setup-report.txt'

            Test-Path -LiteralPath $durablePath -PathType Leaf | Should -BeTrue
            @($output | ForEach-Object { [string]$_ }) | Should -Contain "[INFO] Main setup log: $durablePath"
            [string]$output[-1] | Should -Be $durablePath
        }

        It 'finalizes and reports logging for every setup exit including failure and 3010' {
            $setupPath = Join-Path $script:repositoryRoot 'setup-scripts/setup.ps1'
            $tokens = $null
            $parseErrors = $null
            $setupAst = [System.Management.Automation.Language.Parser]::ParseFile($setupPath, [ref]$tokens, [ref]$parseErrors)
            $parseErrors.Count | Should -Be 0

            $exitStatements = @($setupAst.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.ExitStatementAst]
            }, $true))
            $exitStatements.Count | Should -BeGreaterThan 0
            @($exitStatements | Where-Object { $_.Pipeline.Extent.Text -eq '3010' }).Count | Should -BeGreaterThan 0

            foreach ($exitStatement in $exitStatements) {
                $ancestor = $exitStatement.Parent
                $isProtected = $false
                while ($ancestor) {
                    if ($ancestor -is [System.Management.Automation.Language.TryStatementAst] -and
                        $ancestor.Finally -and
                        $ancestor.Finally.Extent.Text -match 'Complete-DotfilesSetupLogging') {
                        $isProtected = $true
                        break
                    }
                    $ancestor = $ancestor.Parent
                }
                if (-not $isProtected) {
                    throw "Exit '$($exitStatement.Extent.Text)' is not protected by durable transcript finalization."
                }
            }

            $topLevelFinalizer = @($setupAst.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.CommandAst] -and
                    $node.GetCommandName() -eq 'Complete-DotfilesSetupLogging'
            }, $true))
            $topLevelFinalizer.Count | Should -Be 1
        }

        It 'keeps transcript cleanup failure best-effort and reports the retained fallback' {
            $fallbackDirectory = Join-Path $TestDrive 'cleanup-fallback'
            $cloneDirectory = Join-Path $TestDrive 'cleanup-clone'
            $fallbackPath = Join-Path $fallbackDirectory 'setup-cleanup.txt'
            New-Item -ItemType Directory -Path $fallbackDirectory, $cloneDirectory | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $cloneDirectory '.git') | Out-Null
            Set-Content -LiteralPath $fallbackPath -Value 'cleanup failure transcript'
            Mock Stop-Transcript { }
            Mock Move-Item { throw [System.IO.IOException]::new('simulated cleanup failure') }

            $output = @(Complete-DotfilesSetupLogging -LogFilePath $fallbackPath -DotfilesDirectory $cloneDirectory 6>&1 3>&1)

            Test-Path -LiteralPath $fallbackPath -PathType Leaf | Should -BeTrue
            @($output | ForEach-Object { [string]$_ }) | Should -Contain "[WARNING] Cannot retain setup transcript in persistent clone logs: simulated cleanup failure"
            @($output | ForEach-Object { [string]$_ }) | Should -Contain "[INFO] Main setup log: $fallbackPath"
            [string]$output[-1] | Should -Be $fallbackPath
        }

        It 'reports the source when a failed move leaves a stale destination collision' {
            $fallbackDirectory = Join-Path $TestDrive 'collision-fallback'
            $cloneDirectory = Join-Path $TestDrive 'collision-clone'
            $fallbackPath = Join-Path $fallbackDirectory 'setup-collision.txt'
            $destinationPath = Join-Path $cloneDirectory 'logs/setup-collision.txt'
            New-Item -ItemType Directory -Path $fallbackDirectory, (Join-Path $cloneDirectory '.git'), (Split-Path -Parent $destinationPath) | Out-Null
            Set-Content -LiteralPath $fallbackPath -Value 'CURRENT'
            Set-Content -LiteralPath $destinationPath -Value 'STALE'
            Mock Stop-Transcript { }
            Mock Move-Item { throw [System.IO.IOException]::new('stale destination collision') }

            $output = @(Complete-DotfilesSetupLogging -LogFilePath $fallbackPath -DotfilesDirectory $cloneDirectory 6>&1)
            $textOutput = @($output | ForEach-Object { [string]$_ })

            $textOutput | Should -Contain "[INFO] Main setup log: $fallbackPath"
            [string]$output[-1] | Should -Be $fallbackPath
            Get-Content -LiteralPath $output[-1] | Should -Be 'CURRENT'
            Get-Content -LiteralPath $destinationPath | Should -Be 'STALE'
        }

        It 'reports the destination when a move fails after creating it' {
            $fallbackDirectory = Join-Path $TestDrive 'destination-fallback'
            $cloneDirectory = Join-Path $TestDrive 'destination-clone'
            $fallbackPath = Join-Path $fallbackDirectory 'setup-destination.txt'
            $destinationPath = Join-Path $cloneDirectory 'logs/setup-destination.txt'
            New-Item -ItemType Directory -Path $fallbackDirectory, (Join-Path $cloneDirectory '.git') | Out-Null
            Set-Content -LiteralPath $fallbackPath -Value 'destination transcript'
            Mock Stop-Transcript { }
            Mock Move-Item {
                New-Item -ItemType Directory -Path (Split-Path -Parent $Destination) -Force | Out-Null
                [System.IO.File]::Move($LiteralPath, $Destination)
                throw [System.IO.IOException]::new('post-move failure')
            }

            $durablePath = Complete-DotfilesSetupLogging -LogFilePath $fallbackPath -DotfilesDirectory $cloneDirectory

            $durablePath | Should -Be $destinationPath
            Test-Path -LiteralPath $destinationPath -PathType Leaf | Should -BeTrue
            Test-Path -LiteralPath $fallbackPath | Should -BeFalse
        }

        It 'warns without reporting a path when a failed move leaves no transcript' {
            $fallbackDirectory = Join-Path $TestDrive 'missing-after-move-fallback'
            $cloneDirectory = Join-Path $TestDrive 'missing-after-move-clone'
            $fallbackPath = Join-Path $fallbackDirectory 'setup-missing-after-move.txt'
            New-Item -ItemType Directory -Path $fallbackDirectory, (Join-Path $cloneDirectory '.git') | Out-Null
            Set-Content -LiteralPath $fallbackPath -Value 'vanishing transcript'
            Mock Stop-Transcript { }
            Mock Move-Item {
                Remove-Item -LiteralPath $LiteralPath -Force
                throw [System.IO.IOException]::new('destructive move failure')
            }

            $output = @(Complete-DotfilesSetupLogging -LogFilePath $fallbackPath -DotfilesDirectory $cloneDirectory 6>&1 3>&1)
            $textOutput = @($output | ForEach-Object { [string]$_ })

            Test-Path -LiteralPath $fallbackPath | Should -BeFalse
            $textOutput | Should -Contain '[WARNING] Setup transcript was not found at the source or destination after the move failure.'
            @($textOutput | Where-Object { $_ -match 'Main setup log:' }).Count | Should -Be 0
            @($output | Where-Object { $_ -is [string] -and $_ -eq $fallbackPath }).Count | Should -Be 0
        }

        It 'does not replace a primary setup failure or reboot-required status when cleanup fails' {
            $fallbackDirectory = Join-Path $TestDrive 'primary-fallback'
            $cloneDirectory = Join-Path $TestDrive 'primary-clone'
            New-Item -ItemType Directory -Path $fallbackDirectory, $cloneDirectory | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $cloneDirectory '.git') | Out-Null
            Mock Stop-Transcript { }
            Mock Move-Item { throw [System.IO.IOException]::new('simulated cleanup failure') }

            $failureLogPath = Join-Path $fallbackDirectory 'setup-primary-failure.txt'
            Set-Content -LiteralPath $failureLogPath -Value 'primary failure transcript'
            $caughtMessage = $null
            try {
                try {
                    throw [System.InvalidOperationException]::new('primary setup failure')
                }
                finally {
                    Complete-DotfilesSetupLogging -LogFilePath $failureLogPath -DotfilesDirectory $cloneDirectory | Out-Null
                }
            }
            catch {
                $caughtMessage = $_.Exception.Message
            }
            $caughtMessage | Should -Be 'primary setup failure'

            $restartLogPath = Join-Path $fallbackDirectory 'setup-restart.txt'
            Set-Content -LiteralPath $restartLogPath -Value 'restart transcript'
            $setupExitCode = $null
            try {
                $setupExitCode = 3010
            }
            finally {
                Complete-DotfilesSetupLogging -LogFilePath $restartLogPath -DotfilesDirectory $cloneDirectory | Out-Null
            }
            $setupExitCode | Should -Be 3010
        }
    }

    Context 'Windows Terminal configuration' {
        It 'does not contain machine-specific user paths or WSL distribution IDs' {
            $settingsPath = Join-Path $script:repositoryRoot 'dotfiles-configurations/windows-terminal-settings.json.example'
            $settings = Get-Content -LiteralPath $settingsPath -Raw
            if ($settings -match '(?i)C:\\\\Users\\\\') {
                throw 'Windows Terminal baseline settings must not contain a machine-specific user path.'
            }
            if ($settings -match '(?i)--distribution-id') {
                throw 'Windows Terminal baseline settings must let Windows Terminal discover WSL distributions dynamically.'
            }
        }

        It 'requires elevation only where genuinely needed' {
            $configPath = Join-Path $script:repositoryRoot 'dotfiles-configurations/setup-modules.json.example'
            $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
            $terminalModule = @($config.settings.base | Where-Object { $_.script -eq 'Install-WindowsTerminalSettings.ps1' })[0]
            $ompModule = @($config.settings.pwsh | Where-Object { $_.script -eq 'Install-OmpConfig.ps1' })[0]

            if ($terminalModule.requiresAdmin) {
                throw 'Windows Terminal settings are generated in place under LOCALAPPDATA and must not require elevation.'
            }
            if ($ompModule.requiresAdmin) {
                throw 'Oh My Posh theme deployment must not require elevation.'
            }
        }

        It 'installs the required Nerd Font as part of the base settings' {
            $configPath = Join-Path $script:repositoryRoot 'dotfiles-configurations/setup-modules.json.example'
            $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
            $baseScripts = @($config.settings.base.script)

            if ($baseScripts -notcontains 'Install-NerdFont.ps1') {
                throw 'The base settings must install the Nerd Font.'
            }
        }

        It 'deploys Oh My Posh themes without Administrator privileges' {
            $modulePath = Join-Path $script:repositoryRoot 'setup-modules/Install-OmpConfig.ps1'
            $module = Get-Content -LiteralPath $modulePath -Raw

            if ($module -notmatch 'ItemType HardLink' -or $module -notmatch 'Copy-Item') {
                throw 'Oh My Posh themes must use a hard link with a copy fallback.'
            }
            if ($module -match 'Test-IsElevated') {
                throw 'Oh My Posh theme deployment must not require an elevated process.'
            }
        }
    }

    Context 'Failure propagation' {
        It 'fails the package module when one or more Winget installs fail' {
            $modulePath = Join-Path $script:repositoryRoot 'setup-modules/Install-WingetPackages.ps1'
            $module = Get-Content -LiteralPath $modulePath -Raw

            if ($module -notmatch '\$failedPackages\.Add\(\$packageId\)') {
                throw 'Install-WingetPackages.ps1 must record failed package installs.'
            }
            if ($module -notmatch 'throw "Winget failed to install') {
                throw 'Install-WingetPackages.ps1 must fail after package installation errors.'
            }
        }

        It 'treats Winget as a required bootstrap prerequisite' {
            $functionsPath = Join-Path $script:repositoryRoot 'setup-scripts/setup-functions.ps1'
            $functions = Get-Content -LiteralPath $functionsPath -Raw

            if ($functions -notmatch 'Winget is required to install bootstrap prerequisites') {
                throw 'Bootstrap prerequisites must fail explicitly when Winget is unavailable.'
            }
        }

        It 'uses PowerShell error handling for Windows optional features' {
            $modulePath = Join-Path $script:repositoryRoot 'setup-modules/Configure-WindowsFeatures.ps1'
            $module = Get-Content -LiteralPath $modulePath -Raw

            if ($module -notmatch 'Get-WindowsOptionalFeature.+-ErrorAction Stop') {
                throw 'Get-WindowsOptionalFeature must fail when a selected feature cannot be queried.'
            }
            if ($module -match "Could not find feature '.+'[\s\S]*?continue") {
                throw 'Selected Windows features must not be skipped when unavailable.'
            }
            if ($module -match '\$LASTEXITCODE') {
                throw 'PowerShell cmdlet failures must not be inferred from LASTEXITCODE.'
            }
            if ($module -notmatch 'Enable-WindowsOptionalFeature.+-ErrorAction Stop') {
                throw 'Enable-WindowsOptionalFeature must emit a terminating error on failure.'
            }
        }

        It 'uses PowerShell error handling for Windows capabilities' {
            $modulePath = Join-Path $script:repositoryRoot 'setup-modules/Configure-WindowsCapabilities.ps1'
            $module = Get-Content -LiteralPath $modulePath -Raw

            if ($module -notmatch 'Get-WindowsCapability.+-ErrorAction Stop') {
                throw 'Get-WindowsCapability must fail when a selected capability cannot be queried.'
            }
            if ($module -notmatch 'Add-WindowsCapability.+-ErrorAction Stop') {
                throw 'Add-WindowsCapability must emit a terminating error on failure.'
            }
            if ($module -match 'Add-WindowsCapability.+-NoRestart') {
                throw 'Add-WindowsCapability does not support the NoRestart parameter in Windows PowerShell 5.1.'
            }
            if ($module -match '\$LASTEXITCODE') {
                throw 'PowerShell cmdlet failures must not be inferred from LASTEXITCODE.'
            }
            if ($module -notmatch "State -eq 'Installed'" -or $module -notmatch "State -eq 'NotPresent'") {
                throw 'Windows capability installation must explicitly handle Installed and NotPresent states.'
            }
        }

        It 'uses Windows PowerShell 5.1 for DISM modules in both launch paths' {
            $setupPath = Join-Path $script:repositoryRoot 'setup-scripts/setup.ps1'
            $setup = Get-Content -LiteralPath $setupPath -Raw

            if ($setup -notmatch 'WindowsPowerShell\\v1\.0\\powershell\.exe') {
                throw 'Windows DISM modules must use the in-box Windows PowerShell host.'
            }
            if ($setup -notmatch 'Start-Process\s+-FilePath\s+\$moduleHost' -or $setup -notmatch '&\s+\$moduleHost\s+@moduleArguments') {
                throw 'Elevated and already-elevated module launches must use the selected module host.'
            }
            if ($setup -notmatch "Configure-WindowsFeatures\.ps1.+Configure-WindowsCapabilities\.ps1" -or $setup -notmatch "else\s*\{\s*'pwsh\.exe'\s*\}") {
                throw 'Only Windows DISM modules must use Windows PowerShell 5.1; other modules must remain on PowerShell 7.'
            }
        }

        It 'writes an independent transcript for the elevated Windows feature module' {
            $modulePath = Join-Path $script:repositoryRoot 'setup-modules/Configure-WindowsFeatures.ps1'
            $setupPath = Join-Path $script:repositoryRoot 'setup-scripts/setup.ps1'
            $module = Get-Content -LiteralPath $modulePath -Raw
            $setup = Get-Content -LiteralPath $setupPath -Raw

            if ($module -notmatch 'Start-Logging\s+-LogFilePath\s+\$LogFilePath\s+-PassThru\s+-RequireRequestedPath') {
                throw 'The elevated Windows feature module must start and capture its own required transcript path.'
            }
            if ($module -notmatch 'Stop-Logging') {
                throw 'The Windows feature module must close its transcript on completion and failure.'
            }
            if ($setup -notmatch 'Write-ModuleLogLocation\s+-ModuleLogFile\s+\$moduleLogFile' -or $setup -notmatch 'Test-Path\s+-LiteralPath\s+\$ModuleLogFile\s+-PathType\s+Leaf') {
                throw 'Setup must report only a concrete module log file that actually exists.'
            }
            if ($setup -notmatch '\$moduleArguments\s*\+=\s*@\(''-LogFilePath'',\s*\$moduleLogFile\)' -or $setup -notmatch '&\s+\$moduleHost\s+@moduleArguments') {
                throw 'Already-elevated and newly elevated module launches must receive the same explicit log path and selected host.'
            }
            if ($setup -notmatch '\$logFile\s*=\s*Start-Logging\s+-LogFilePath\s+\$logFile\s+-PassThru') {
                throw 'The parent setup summary must retain the actual transcript path after fallback.'
            }
        }

        It 'writes an independent transcript for the elevated Windows capability module' {
            $modulePath = Join-Path $script:repositoryRoot 'setup-modules/Configure-WindowsCapabilities.ps1'
            $setupPath = Join-Path $script:repositoryRoot 'setup-scripts/setup.ps1'
            $module = Get-Content -LiteralPath $modulePath -Raw
            $setup = Get-Content -LiteralPath $setupPath -Raw

            if ($module -notmatch 'Start-Logging\s+-LogFilePath\s+\$LogFilePath\s+-PassThru\s+-RequireRequestedPath' -or $module -notmatch 'Stop-Logging') {
                throw 'The elevated Windows capability module must own and close its transcript.'
            }
            if ($setup -notmatch "Configure-WindowsCapabilities\.ps1.+Set-UserHomeAlias\.ps1") {
                throw 'Setup must handle Configure-WindowsCapabilities.ps1 before Set-UserHomeAlias.ps1.'
            }
        }

        It 'stops setup with the Windows reboot-required exit code before running later modules' {
            $modulePath = Join-Path $script:repositoryRoot 'setup-modules/Configure-WindowsFeatures.ps1'
            $setupPath = Join-Path $script:repositoryRoot 'setup-scripts/setup.ps1'
            $module = Get-Content -LiteralPath $modulePath -Raw
            $setup = Get-Content -LiteralPath $setupPath -Raw

            if ($module -notmatch 'if \(\$restartNeeded\)[\s\S]*?\$moduleExitCode\s*=\s*3010' -or $module -notmatch 'exit \$moduleExitCode') {
                throw 'The Windows feature module must return exit code 3010 when a reboot is required.'
            }

            $restartHandlerIndex = $setup.IndexOf('$moduleExitCode -eq 3010')
            $successHandlerIndex = $setup.IndexOf('$moduleExitCode -eq 0')
            if ($restartHandlerIndex -lt 0 -or $successHandlerIndex -lt 0 -or $restartHandlerIndex -gt $successHandlerIndex) {
                throw 'Setup must stop on exit code 3010 before treating later module outcomes.'
            }
            if ($setup -notmatch 'Exit 3010') {
                throw 'Setup must propagate the reboot-required exit code to its caller.'
            }

            $capabilityModulePath = Join-Path $script:repositoryRoot 'setup-modules/Configure-WindowsCapabilities.ps1'
            $capabilityModule = Get-Content -LiteralPath $capabilityModulePath -Raw
            if ($capabilityModule -notmatch 'if \(\$restartNeeded\)[\s\S]*?\$moduleExitCode\s*=\s*3010' -or $capabilityModule -notmatch 'exit \$moduleExitCode') {
                throw 'The Windows capability module must return exit code 3010 when a reboot is required.'
            }
        }

        It 'propagates setup exit codes through the Git-free installer' {
            $installerPath = Join-Path $script:repositoryRoot 'setup-scripts/install.ps1'
            $installer = Get-Content -LiteralPath $installerPath -Raw

            if ($installer -notmatch '\$setupExitCode\s*=\s*\$LASTEXITCODE') {
                throw 'The Git-free installer must capture the setup exit code.'
            }
            if ($installer -notmatch 'exit \$setupExitCode') {
                throw 'The Git-free installer must propagate setup failures and reboot-required status.'
            }
        }

        It 'fails when archive extraction or a configured module is unavailable' {
            $installerPath = Join-Path $script:repositoryRoot 'setup-scripts/install.ps1'
            $setupPath = Join-Path $script:repositoryRoot 'setup-scripts/setup.ps1'
            $installer = Get-Content -LiteralPath $installerPath -Raw
            $setup = Get-Content -LiteralPath $setupPath -Raw

            if ($installer -notmatch "throw `"Failed to extract") {
                throw 'Archive extraction failures must terminate the Git-free installer.'
            }
            if ($setup -match 'Module script not found:.+Skipping') {
                throw 'Missing configured modules must not be skipped.'
            }
        }

        It 'uses Winget exit codes to detect installed packages' {
            $modulePath = Join-Path $script:repositoryRoot 'setup-modules/Install-WingetPackages.ps1'
            $module = Get-Content -LiteralPath $modulePath -Raw

            if ($module -match '\$listOutput\s+-match') {
                throw 'Installed package detection must not parse Winget display text.'
            }
            if ($module -notmatch '\$isInstalled\s*=\s*\$LASTEXITCODE\s+-eq\s+0') {
                throw 'Installed package detection must use the Winget exit code.'
            }
        }

        It 'elevates only missing machine-scoped Winget install mutations' {
            $modulePath = Join-Path $script:repositoryRoot 'setup-modules/Install-WingetPackages.ps1'
            $module = Get-Content -LiteralPath $modulePath -Raw

            $trustedResolutionIndex = $module.IndexOf("ExportedCommands['Get-AppxPackage']")
            $installedCheckIndex = $module.IndexOf('if ($isInstalled)')
            $machineScopeIndex = $module.IndexOf("if (`$packageScope -eq 'machine')")
            $elevatedInstallIndex = $module.IndexOf('Microsoft.PowerShell.Management\Start-Process')

            if ($trustedResolutionIndex -lt 0 -or $module -notmatch 'Microsoft\.DesktopAppInstaller') {
                throw 'Winget must be resolved from the registered Windows App Installer package.'
            }
            if ($module -notmatch "GetFolderPath\(\[Environment\+SpecialFolder\]::Windows\)" -or
                $module -notmatch "WindowsPowerShell\\v1\.0\\Modules\\Appx\\Appx\.psd1" -or
                $module -notmatch "Import-Module.+-PassThru") {
                throw 'Get-AppxPackage must come from the explicitly imported in-box Appx module.'
            }
            if ($module -notmatch "GetFolderPath\(\[Environment\+SpecialFolder\]::ProgramFiles\)" -or $module -notmatch 'GetFullPath') {
                throw 'The resolved Winget executable must be constrained to the canonical Program Files WindowsApps root.'
            }
            if ($module -match '\$env:ProgramFiles') {
                throw 'The trusted WindowsApps root must not depend on caller-controlled environment variables.'
            }
            if ($module -match 'Get-Command\s+(?:-Name\s+)?[''"]?winget') {
                throw 'The elevated Winget executable must not be selected from the caller-controlled PATH.'
            }
            if ($installedCheckIndex -lt 0 -or $machineScopeIndex -lt $installedCheckIndex -or $elevatedInstallIndex -lt $machineScopeIndex) {
                throw 'Installed-package checks must happen before machine-scoped elevation.'
            }
            if ($module -notmatch 'Microsoft\.PowerShell\.Management\\Start-Process\s+-FilePath\s+\$wingetPath\s+-ArgumentList\s+\$installArguments\s+-Verb\s+RunAs\s+-Wait\s+-PassThru') {
                throw 'Missing machine-scoped installs must invoke the resolved Winget executable through an elevated process and wait for its result.'
            }
            if ($module -notmatch '\$installExitCode\s*=\s*if \(\$null -ne \$installProcess -and \$null -ne \$installProcess\.ExitCode\) \{ \$installProcess\.ExitCode \} else \{ 1 \}') {
                throw 'Elevated Winget installs must capture the child process exit code or coalesce failures to a non-zero result.'
            }
            if ($module -notmatch 'else\s*\{\s*&\s+\$wingetPath\s+@installArguments\s*\$installExitCode\s*=\s*\$LASTEXITCODE') {
                throw 'User-scoped and unscoped installs must invoke Winget directly and capture its exit code.'
            }
            if ($module -match '&\s+winget\b') {
                throw 'Winget invocations must use the explicitly resolved executable path.'
            }
            if ($module -notmatch '\$packageIdentifierPattern\s*=' -or
                $module -notmatch '\$packageId\.Length\s+-gt\s+128' -or
                $module -notmatch '\$packageId\s+-notmatch\s+\$packageIdentifierPattern') {
                throw 'Package IDs must be validated against the Winget PackageIdentifier grammar before crossing the elevated ArgumentList boundary.'
            }
        }

        It 'rejects package identifiers that could split elevated Winget arguments' {
            $modulePath = Join-Path $script:repositoryRoot 'setup-modules/Install-WingetPackages.ps1'
            $module = Get-Content -LiteralPath $modulePath -Raw
            $patternMatch = [regex]::Match($module, '\$packageIdentifierPattern\s*=\s*''([^'']+)''', [Text.RegularExpressions.RegexOptions]::CultureInvariant)
            if (-not $patternMatch.Success) {
                throw 'Could not read the production Winget PackageIdentifier pattern.'
            }
            $packageIdentifierPattern = $patternMatch.Groups[1].Value

            foreach ($invalidId in @(
                'gerardog.gsudo --scope user',
                "gerardog.gsudo`t--source msstore",
                "gerardog.gsudo`n--scope user",
                'gerardog."gsudo"',
                'singleSegment',
                'Publisher..Package'
            )) {
                if ($invalidId.Length -le 128 -and $invalidId -match $packageIdentifierPattern) {
                    throw "Unsafe package ID unexpectedly passed validation: $invalidId"
                }
            }

            foreach ($validId in @('gerardog.gsudo', 'Microsoft.PowerShell', 'Python.Python.3.13')) {
                if ($validId.Length -gt 128 -or $validId -notmatch $packageIdentifierPattern) {
                    throw "Valid package ID unexpectedly failed validation: $validId"
                }
            }
        }
    }

    Context 'Git-free branch selection' {
        It 'passes the downloaded branch to the setup orchestrator' {
            $installerPath = Join-Path $script:repositoryRoot 'setup-scripts/install.ps1'
            $installer = Get-Content -LiteralPath $installerPath -Raw

            if ($installer -notmatch [regex]::Escape('& .\setup-scripts\setup.ps1 -BootstrapBranch $branch')) {
                throw 'The Git-free installer must keep setup on the downloaded branch.'
            }
        }

        It 'propagates non-interactive configuration through the bootstrap' {
            $installerPath = Join-Path $script:repositoryRoot 'setup-scripts/install.ps1'
            $setupPath = Join-Path $script:repositoryRoot 'setup-scripts/setup.ps1'
            $installer = Get-Content -LiteralPath $installerPath -Raw
            $setup = Get-Content -LiteralPath $setupPath -Raw

            if ($installer -notmatch '-NonInteractive:\$NonInteractive') {
                throw 'The Git-free installer must pass NonInteractive to setup.ps1.'
            }
            if ($setup -notmatch 'Get-DotfilesBootstrapVariables -NonInteractive:\$NonInteractive') {
                throw 'The setup orchestrator must pass NonInteractive to configuration initialization.'
            }
        }

        It 'relaunches Windows PowerShell callers in PowerShell 7 before Git operations' {
            $setupPath = Join-Path $script:repositoryRoot 'setup-scripts/setup.ps1'
            $setup = Get-Content -LiteralPath $setupPath -Raw
            $relaunchIndex = $setup.IndexOf('$PSVersionTable.PSEdition -ne "Core"')
            $cloneIndex = $setup.IndexOf('git clone')

            if ($relaunchIndex -lt 0 -or $cloneIndex -lt 0 -or $relaunchIndex -gt $cloneIndex) {
                throw 'Windows PowerShell must relaunch in PowerShell 7 before Git writes progress to stderr.'
            }
            if ($setup -notmatch '& \$pwshCommand\.Source @pwshArguments') {
                throw 'The setup script must execute its PowerShell 7 relaunch arguments.'
            }
        }

        It 'installs bootstrap prerequisites per-user without updating legacy PowerShellGet' {
            $functionsPath = Join-Path $script:repositoryRoot 'setup-scripts/setup-functions.ps1'
            $functions = Get-Content -LiteralPath $functionsPath -Raw

            if ($functions -notmatch "'--scope', 'user'") {
                throw 'Git and PowerShell bootstrap prerequisites must request user scope.'
            }
            if ($functions -match 'Install-Module -Name PowerShellGet') {
                throw 'Bootstrap must not update PowerShellGet in the active Windows PowerShell process.'
            }
        }

        It 'passes declarative package metadata to Winget installs' {
            $modulePath = Join-Path $script:repositoryRoot 'setup-modules/Install-WingetPackages.ps1'
            $module = Get-Content -LiteralPath $modulePath -Raw

            if ($module -notmatch '\$packageEntry\.scope') {
                throw 'Winget package objects must expose their configured scope.'
            }
            if ($module -notmatch '@\(''--scope'', \$packageScope\)') {
                throw 'Configured package scopes must be passed to Winget.'
            }
            if ($module -notmatch '\$packageEntry\.installerType') {
                throw 'Winget package objects must expose their configured installer type.'
            }
            if ($module -notmatch '@\(''--installer-type'', \$packageInstallerType\)') {
                throw 'Configured package installer types must be passed to Winget.'
            }
        }

        It 'pins bootstrap and package installs to the Winget community source' {
            $functionsPath = Join-Path $script:repositoryRoot 'setup-scripts/setup-functions.ps1'
            $modulePath = Join-Path $script:repositoryRoot 'setup-modules/Install-WingetPackages.ps1'
            $functions = Get-Content -LiteralPath $functionsPath -Raw
            $module = Get-Content -LiteralPath $modulePath -Raw

            $bootstrapSourcePins = [regex]::Matches($functions, "'--source', 'winget'")
            if ($bootstrapSourcePins.Count -lt 2) {
                throw 'PowerShell and Git bootstrap installs must both select the Winget community source explicitly.'
            }
            if ($module -notmatch "'--source', 'winget'") {
                throw 'Declarative package installs must select the Winget community source explicitly.'
            }
        }
    }

    Context 'Default configuration consistency' {
        It 'orders the RSAT Server Manager prerequisite before the Active Directory capability' {
            $capabilitiesPath = Join-Path $script:repositoryRoot 'dotfiles-configurations/windows-capabilities.json.example'
            $capabilities = Get-Content -LiteralPath $capabilitiesPath -Raw | ConvertFrom-Json
            $rsatActiveDirectory = @($capabilities.'rsat-active-directory')
            $expected = @(
                'Rsat.ServerManager.Tools~~~~0.0.1.0',
                'Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0'
            )

            if (($rsatActiveDirectory -join ',') -ne ($expected -join ',')) {
                throw "The RSAT Active Directory group must preserve dependency order, got '$($rsatActiveDirectory -join ',')'."
            }
        }

        It 'uses only VirtualMachinePlatform for the WSL 2 feature group' {
            $featuresPath = Join-Path $script:repositoryRoot 'dotfiles-configurations/windows-features.json.example'
            $features = Get-Content -LiteralPath $featuresPath -Raw | ConvertFrom-Json
            $wslFeatures = @($features.wsl)

            if (($wslFeatures -join ',') -ne 'VirtualMachinePlatform') {
                throw "The WSL 2 feature group must contain only VirtualMachinePlatform, got '$($wslFeatures -join ',')'."
            }
        }

        It 'installs the package groups required by default settings' {
            $bootstrapPath = Join-Path $script:repositoryRoot 'dotfiles-configurations/dotfiles-bootstrap-variables.json.example'
            $modulesPath = Join-Path $script:repositoryRoot 'dotfiles-configurations/setup-modules.json.example'
            $packagesPath = Join-Path $script:repositoryRoot 'dotfiles-configurations/winget-packages.json.example'
            $bootstrap = Get-Content -LiteralPath $bootstrapPath -Raw | ConvertFrom-Json
            $modules = Get-Content -LiteralPath $modulesPath -Raw | ConvertFrom-Json
            $packages = Get-Content -LiteralPath $packagesPath -Raw | ConvertFrom-Json

            $required = Get-DotfilesRequiredPackageGroup -SetupConfig $modules -SelectedSettings $bootstrap.INSTALL_SETTINGS
            $missing = @($required | Where-Object { $bootstrap.INSTALL_PACKAGES -notcontains $_ })
            if ($missing.Count -gt 0) {
                throw "Default settings require missing package groups: $($missing -join ', ')."
            }
            if ($packages.PSObject.Properties.Name -contains 'Packages') {
                throw "The obsolete, ignored 'Packages' property must not be present."
            }
            $pwshIds = @($packages.pwsh | ForEach-Object { if ($_ -is [string]) { $_ } else { $_.id } })
            if ($pwshIds -notcontains 'JanDeDobbeleer.OhMyPosh') {
                throw 'The pwsh package group must install Oh My Posh.'
            }

            $baseScopes = @{}
            foreach ($package in $packages.base) {
                if ($package -isnot [string]) {
                    $baseScopes[$package.id] = $package.scope
                }
            }
            foreach ($packageId in @('Git.Git', 'Microsoft.PowerShell', 'Microsoft.VisualStudioCode', 'Microsoft.WindowsTerminal')) {
                if ($baseScopes[$packageId] -ne 'user') {
                    throw "Base package '$packageId' must use user scope."
                }
            }

            $poweruserScopes = @{}
            foreach ($package in $packages.poweruser) {
                if ($package -isnot [string]) {
                    $poweruserScopes[$package.id] = $package.scope
                }
            }
            if ($poweruserScopes['gerardog.gsudo'] -ne 'machine') {
                throw "Power-user package 'gerardog.gsudo' must use machine scope."
            }

            $browsersScopes = @{}
            foreach ($package in $packages.browsers) {
                if ($package -isnot [string]) {
                    $browsersScopes[$package.id] = $package.scope
                }
            }
            if ($browsersScopes['Microsoft.Edge'] -ne 'machine') {
                throw "Browsers package 'Microsoft.Edge' must use machine scope."
            }

        }

        It 'keeps excluded packages out and Power BI in its machine-scoped group' {
            $packagesPath = Join-Path $script:repositoryRoot 'dotfiles-configurations/winget-packages.json.example'
            $bootstrapPath = Join-Path $script:repositoryRoot 'dotfiles-configurations/dotfiles-bootstrap-variables.json.example'
            $packages = Get-Content -LiteralPath $packagesPath -Raw | ConvertFrom-Json
            $bootstrap = Get-Content -LiteralPath $bootstrapPath -Raw | ConvertFrom-Json
            $allPackageIds = @($packages.PSObject.Properties.Value | ForEach-Object {
                $_ | ForEach-Object { if ($_ -is [string]) { $_ } else { $_.id } }
            })

            foreach ($excludedPackageId in @('Microsoft.365Copilot', 'Microsoft.Sysinternals.Suite')) {
                if ($allPackageIds -contains $excludedPackageId) {
                    throw "Excluded package '$excludedPackageId' must not be in the install pool."
                }
            }

            if ($packages.PSObject.Properties.Name -cnotcontains 'PowerBI') {
                throw "The PowerBI package group must be defined with exact casing."
            }
            $powerBiPackages = @($packages.PowerBI)
            if ($powerBiPackages.Count -ne 1 -or $powerBiPackages[0].id -ne 'Microsoft.PowerBI' -or $powerBiPackages[0].scope -ne 'machine') {
                throw "The PowerBI group must contain only Microsoft.PowerBI with machine scope."
            }
            if ($bootstrap.INSTALL_PACKAGES -notcontains 'PowerBI') {
                throw "The default package selection must include the PowerBI group."
            }
        }

        It 'uses upstream-compatible scope and installer-type constraints for the default package pool' {
            $packagesPath = Join-Path $script:repositoryRoot 'dotfiles-configurations/winget-packages.json.example'
            $packages = Get-Content -LiteralPath $packagesPath -Raw | ConvertFrom-Json
            $packageMetadata = @{}
            $scopeNeutralWixPackages = @('Microsoft.Azd', 'Microsoft.WSL')

            foreach ($group in $packages.PSObject.Properties) {
                foreach ($packageEntry in $group.Value) {
                    if ($packageEntry -is [string]) {
                        throw "Package '$packageEntry' must use an object entry with explicit metadata."
                    }
                    $packageScope = [string]$packageEntry.scope
                    $packageInstallerType = [string]$packageEntry.installerType
                    if ([string]::IsNullOrWhiteSpace($packageScope) -and $packageEntry.id -notin $scopeNeutralWixPackages) {
                        throw "Package '$($packageEntry.id)' must declare an explicit scope."
                    }
                    $packageMetadata[$packageEntry.id] = [pscustomobject]@{
                        Scope = $packageScope
                        InstallerType = $packageInstallerType
                    }
                }
            }

            if ($packageMetadata.ContainsKey('Microsoft.AppInstaller')) {
                throw 'Microsoft.AppInstaller must not be installed through Winget itself.'
            }

            foreach ($packageId in $scopeNeutralWixPackages) {
                if (-not [string]::IsNullOrWhiteSpace($packageMetadata[$packageId].Scope)) {
                    throw "Package '$packageId' must omit scope because its upstream WiX installer does not declare one."
                }
                if ($packageMetadata[$packageId].InstallerType -ne 'wix') {
                    throw "Package '$packageId' must select the upstream WiX installer explicitly."
                }
            }

            foreach ($packageId in @(
                'Docker.DockerDesktop',
                'gerardog.gsudo',
                'Microsoft.AzureCLI',
                'Microsoft.Edge',
                'Microsoft.Office',
                'Microsoft.PowerBI',
                'Mozilla.Firefox'
            )) {
                if ($packageMetadata[$packageId].Scope -ne 'machine') {
                    throw "Package '$packageId' must use machine scope."
                }
            }
        }

        It 'defines valid package entries with consistent metadata' {
            $packagesPath = Join-Path $script:repositoryRoot 'dotfiles-configurations/winget-packages.json.example'
            $packages = Get-Content -LiteralPath $packagesPath -Raw | ConvertFrom-Json
            $declaredMetadata = [System.Collections.Generic.Dictionary[string, object]]::new(
                [System.StringComparer]::OrdinalIgnoreCase
            )

            foreach ($group in $packages.PSObject.Properties) {
                $seenInGroup = [System.Collections.Generic.HashSet[string]]::new(
                    [System.StringComparer]::OrdinalIgnoreCase
                )

                foreach ($packageEntry in $group.Value) {
                    $packageId = if ($packageEntry -is [string]) { $packageEntry } else { [string]$packageEntry.id }
                    $packageScope = if ($packageEntry -is [string]) { $null } else { [string]$packageEntry.scope }
                    $packageInstallerType = if ($packageEntry -is [string]) { $null } else { [string]$packageEntry.installerType }

                    if ([string]::IsNullOrWhiteSpace($packageScope)) { $packageScope = $null }
                    if ([string]::IsNullOrWhiteSpace($packageInstallerType)) { $packageInstallerType = $null }

                    if ([string]::IsNullOrWhiteSpace($packageId)) {
                        throw "Package group '$($group.Name)' contains an entry without an id."
                    }
                    if (-not $seenInGroup.Add($packageId)) {
                        throw "Package group '$($group.Name)' contains duplicate package '$packageId'."
                    }
                    if ($packageScope -and $packageScope -notin @('user', 'machine')) {
                        throw "Package '$packageId' has unsupported scope '$packageScope'."
                    }
                    if ($packageInstallerType -and $packageInstallerType -notin @('wix')) {
                        throw "Package '$packageId' has unsupported installer type '$packageInstallerType'."
                    }

                    if ($declaredMetadata.ContainsKey($packageId)) {
                        $existingMetadata = $declaredMetadata[$packageId]
                        if ($existingMetadata.Scope -ne $packageScope -or $existingMetadata.InstallerType -ne $packageInstallerType) {
                            throw "Package '$packageId' has conflicting metadata across package groups."
                        }
                    } else {
                        $declaredMetadata[$packageId] = [pscustomobject]@{
                            Scope = $packageScope
                            InstallerType = $packageInstallerType
                        }
                    }
                }
            }
        }

        It 'installs the WSL runtime before Docker Desktop' {
            $packagesPath = Join-Path $script:repositoryRoot 'dotfiles-configurations/winget-packages.json.example'
            $packages = Get-Content -LiteralPath $packagesPath -Raw | ConvertFrom-Json
            $packageIds = @($packages.PSObject.Properties.Value | ForEach-Object {
                $_ | ForEach-Object { if ($_ -is [string]) { $_ } else { $_.id } }
            })
            $wslIndex = [Array]::IndexOf($packageIds, 'Microsoft.WSL')
            $dockerIndex = [Array]::IndexOf($packageIds, 'Docker.DockerDesktop')

            if ($wslIndex -lt 0 -or $dockerIndex -lt 0 -or $wslIndex -gt $dockerIndex) {
                throw "Package 'Microsoft.WSL' must be installed before 'Docker.DockerDesktop'."
            }
        }

        It 'installs known package prerequisites before their dependents' {
            $packagesPath = Join-Path $script:repositoryRoot 'dotfiles-configurations/winget-packages.json.example'
            $packages = Get-Content -LiteralPath $packagesPath -Raw | ConvertFrom-Json
            $dependencyContracts = @(
                [pscustomobject]@{
                    Group = 'wsl'
                    Prerequisite = 'Microsoft.WSL'
                    Dependent = 'Canonical.Ubuntu'
                }
            )

            foreach ($contract in $dependencyContracts) {
                $packageIds = @($packages.($contract.Group) | ForEach-Object {
                    if ($_ -is [string]) { $_ } else { $_.id }
                })
                $prerequisiteIndex = [Array]::IndexOf($packageIds, $contract.Prerequisite)
                $dependentIndex = [Array]::IndexOf($packageIds, $contract.Dependent)

                if ($prerequisiteIndex -lt 0 -or $dependentIndex -lt 0 -or $prerequisiteIndex -gt $dependentIndex) {
                    throw "Package '$($contract.Prerequisite)' must be installed before '$($contract.Dependent)' in group '$($contract.Group)'."
                }
            }
        }
    }
}
