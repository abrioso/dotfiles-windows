function New-DotfilesDiagnosticResult {
    param(
        [ValidateSet('Passed', 'Drift', 'Unknown', 'Skipped')][string]$Status,
        [string]$Message
    )
    [pscustomobject]@{ Status = $Status; Message = $Message }
}

function Add-DotfilesDiagnosticCheck {
    param($Checks, [string]$Category, [string]$Name, [scriptblock]$Probe)
    try {
        $result = & $Probe
        if ($result.Status -notin @('Passed', 'Drift', 'Unknown', 'Skipped')) { throw 'Invalid probe result.' }
    } catch {
        # Native stderr, paths, private configuration and exception text are never reported.
        $result = New-DotfilesDiagnosticResult Unknown 'Query failed or access was denied; state was not verified.'
    }
    $Checks.Add([pscustomobject]@{ Category = $Category; Name = $Name; Status = $result.Status; Message = $result.Message })
}

function Invoke-DotfilesDiagnosticNative {
    param([string]$Command, [string[]]$Arguments, [int]$TimeoutMilliseconds = 15000)
    $application = Get-Command -Name $Command -CommandType Application -ErrorAction Stop | Select-Object -First 1
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $application.Source
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in $Arguments) { $startInfo.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        $null = $process.Start()
        $outputTask = $process.StandardOutput.ReadToEndAsync()
        $errorTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutMilliseconds)) {
            $process.Kill()
            throw 'Diagnostic query timed out.'
        }
        $null = $errorTask.GetAwaiter().GetResult()
        [pscustomobject]@{ ExitCode = $process.ExitCode; Output = $outputTask.GetAwaiter().GetResult() }
    } finally { $process.Dispose() }
}

function Test-DotfilesDiagnosticFile {
    param([string]$Source, [string]$Target)
    if (-not (Test-Path -LiteralPath $Source -PathType Leaf -ErrorAction Stop)) {
        return New-DotfilesDiagnosticResult Unknown 'Source file is unavailable.'
    }
    if (-not (Test-Path -LiteralPath $Target -PathType Leaf -ErrorAction Stop)) {
        return New-DotfilesDiagnosticResult Drift 'Deployed file is missing.'
    }
    if ((Get-FileHash -LiteralPath $Source -ErrorAction Stop).Hash -ne (Get-FileHash -LiteralPath $Target -ErrorAction Stop).Hash) {
        return New-DotfilesDiagnosticResult Drift 'Deployed content differs from this checkout.'
    }
    New-DotfilesDiagnosticResult Passed 'Deployed content matches this checkout.'
}

function Get-DotfilesDiagnosticEnvironmentValue {
    param([string]$Name, [string]$Scope)
    [Environment]::GetEnvironmentVariable($Name, $Scope)
}

function Get-DotfilesSetupDiagnostic {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [switch]$CheckPackages,
        [string]$LocalAppData = $env:LOCALAPPDATA,
        [string]$UserProfile = $env:USERPROFILE,
        [string]$ProfileDirectory = (Split-Path -Parent $PROFILE)
    )
    $checks = [Collections.Generic.List[object]]::new()
    $preview = $null
    try {
        $preview = Get-DotfilesSetupPreview -RepositoryRoot $RepositoryRoot
        if ($null -eq $preview) { throw 'No configuration preview was returned.' }
        $checks.Add([pscustomobject]@{Category='Configuration';Name='Local JSON';Status='Passed';Message='Existing local configuration passed preflight.'})
    } catch {
        $checks.Add([pscustomobject]@{Category='Configuration';Name='Local JSON';Status='Unknown';Message='Configuration could not be validated. Run configure.ps1 and review local JSON before retrying.'})
    }
    if ($preview) {
        $configDirectory = Join-Path $RepositoryRoot 'dotfiles-configurations'
        $scripts = @($preview.Modules.Script)
        $prerequisites = @('pwsh', 'git')
        if ($scripts -contains 'Install-WingetPackages.ps1') { $prerequisites += 'winget' }
        foreach ($command in $prerequisites) {
            Add-DotfilesDiagnosticCheck $checks Prerequisite $command {
                if (Get-Command $command -CommandType Application -ErrorAction SilentlyContinue) {
                    New-DotfilesDiagnosticResult Passed 'Executable is available; version compatibility is not assessed.'
                } else { New-DotfilesDiagnosticResult Drift 'Executable is unavailable in this process PATH.' }
            }
        }
        if ($preview.Features.Count -gt 0) {
            $featureStates = $null
            try { $featureStates = @(Get-CimInstance -ClassName Win32_OptionalFeature -ErrorAction Stop) } catch { }
            foreach ($name in $preview.Features) {
                Add-DotfilesDiagnosticCheck $checks WindowsFeature $name {
                    if ($null -eq $featureStates) { return New-DotfilesDiagnosticResult Unknown 'CIM state is unavailable.' }
                    $matches = @($featureStates | Where-Object Name -IEQ $name)
                    if ($matches.Count -ne 1) { return New-DotfilesDiagnosticResult Unknown 'Requested component was not identified on this OS.' }
                    if ([uint32]$matches[0].InstallState -eq 1) { New-DotfilesDiagnosticResult Passed 'Enabled.' }
                    elseif ([uint32]$matches[0].InstallState -in @(2, 3)) { New-DotfilesDiagnosticResult Drift 'Disabled or absent.' }
                    else { New-DotfilesDiagnosticResult Unknown 'Component state is inconclusive.' }
                }
            }
        }
        foreach ($name in $preview.Capabilities) {
            Add-DotfilesDiagnosticCheck $checks WindowsCapability $name {
                $states = @(Get-WindowsCapability -Online -Name $name -ErrorAction Stop)
                if ($states.Count -ne 1) { return New-DotfilesDiagnosticResult Unknown 'Requested capability was not identified on this OS.' }
                if ($states[0].State -eq 'Installed') { New-DotfilesDiagnosticResult Passed 'Installed.' }
                elseif ($states[0].State -eq 'NotPresent') { New-DotfilesDiagnosticResult Drift 'Not installed.' }
                else { New-DotfilesDiagnosticResult Unknown 'Capability is pending or its state is inconclusive.' }
            }
        }
        if ($scripts -contains 'Install-WingetPackages.ps1') {
            foreach ($package in $preview.Packages) {
                Add-DotfilesDiagnosticCheck $checks Package $package.Id {
                    if (-not $CheckPackages) { return New-DotfilesDiagnosticResult Unknown 'Package query was not enabled. Use -CheckPackages for presence checks.' }
                    $query = Invoke-DotfilesDiagnosticNative winget @('list', '--id', $package.Id, '--exact', '--source', 'winget', '--disable-interactivity')
                    if ($query.ExitCode -ne 0) { return New-DotfilesDiagnosticResult Unknown 'WinGet query did not succeed; absence, source errors and agreements cannot be distinguished.' }
                    $idPattern = '(?im)(?<![\w.-])' + [regex]::Escape($package.Id) + '(?![\w.-])'
                    if ($query.Output -notmatch $idPattern) { return New-DotfilesDiagnosticResult Unknown 'Successful query did not expose the exact ID; presence could not be verified.' }
                    if ($package.Scope -or $package.InstallerType) { return New-DotfilesDiagnosticResult Unknown 'ID was found, but requested scope/installer conformance was not verified.' }
                    New-DotfilesDiagnosticResult Passed 'Exact package ID was found; version is not constrained.'
                }
            }
        }
        if ($scripts -contains 'Set-EnvironmentVariables.ps1') {
            $environment = Read-DotfilesConfigurationObject (Join-Path $configDirectory 'env-variables.json')
            $index = 0
            foreach ($entry in $environment.EnvironmentVariables) {
                $index++
                Add-DotfilesDiagnosticCheck $checks Environment "Entry $index ($($entry.Scope))" {
                    $actual = Get-DotfilesDiagnosticEnvironmentValue -Name $entry.Name -Scope $entry.Scope
                    # Windows removes variables assigned an empty value; null and empty are equivalent.
                    if ([string]$actual -ceq [string]$entry.Value) { New-DotfilesDiagnosticResult Passed 'Persistent value matches configuration.' }
                    else { New-DotfilesDiagnosticResult Drift 'Persistent value is missing or differs from configuration.' }
                }
            }
        }
        if ($scripts -contains 'Apply-GitConfig.ps1') {
            $gitConfig = Read-DotfilesConfigurationObject (Join-Path $configDirectory 'git-variables.json')
            $index = 0
            foreach ($property in $gitConfig.PSObject.Properties) {
                $index++
                Add-DotfilesDiagnosticCheck $checks Git "Setting $index" {
                    $desired = [string]$property.Value
                    if ([string]::IsNullOrWhiteSpace($desired)) { return New-DotfilesDiagnosticResult Skipped 'Empty configured value is intentionally ignored by apply.' }
                    if ($desired -match '[\r\n]') { return New-DotfilesDiagnosticResult Unknown 'Multiline Git values are not assessed.' }
                    $query = Invoke-DotfilesDiagnosticNative git @('config', '--global', '--get-all', '--', $property.Name)
                    if ($query.ExitCode -eq 1) { return New-DotfilesDiagnosticResult Drift 'Global setting is missing.' }
                    if ($query.ExitCode -ne 0) { return New-DotfilesDiagnosticResult Unknown 'Global Git configuration could not be read.' }
                    # Remove one output terminator only: extra empty entries are still drift.
                    $observed = $query.Output -replace '\r?\n\z', ''
                    if ($observed -ceq $desired) { New-DotfilesDiagnosticResult Passed 'Global value matches configuration.' }
                    else { New-DotfilesDiagnosticResult Drift 'Global value differs or has multiple entries.' }
                }
            }
        }
        if ($scripts -contains 'Install-LocalPowerShellProfiles.ps1') {
            $profileFiles = $null
            try { $profileFiles = @(Get-ChildItem (Join-Path $RepositoryRoot 'powershell-profiles') -Filter '*.ps1' -File -ErrorAction Stop) } catch { }
            Add-DotfilesDiagnosticCheck $checks ProfileSource 'Inventory' {
                if (-not $profileFiles) { return New-DotfilesDiagnosticResult Unknown 'Source profiles are unavailable or empty.' }
                New-DotfilesDiagnosticResult Passed 'Source profile inventory is readable.'
            }
            foreach ($file in $profileFiles) {
                Add-DotfilesDiagnosticCheck $checks ProfileCopy $file.Name {
                    Test-DotfilesDiagnosticFile $file.FullName (Join-Path $LocalAppData "dotfiles/powershell-profiles/$($file.Name)")
                }
                Add-DotfilesDiagnosticCheck $checks ProfileStub $file.Name {
                    $target = Join-Path $ProfileDirectory $file.Name
                    if (-not (Test-Path -LiteralPath $target -PathType Leaf -ErrorAction Stop)) { return New-DotfilesDiagnosticResult Drift 'Profile stub is missing.' }
                    $item = Get-Item -LiteralPath $target -Force -ErrorAction Stop
                    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { return New-DotfilesDiagnosticResult Drift 'Legacy profile link has not been replaced by a managed stub.' }
                    $content = Get-Content -LiteralPath $target -Raw -ErrorAction Stop
                    $marker = '# dotfiles-managed stub - real profile lives in LOCALAPPDATA. Do not edit this file.'
                    if (($content -split '\r?\n')[0] -ne $marker) { return New-DotfilesDiagnosticResult Skipped 'User-authored profile is preserved by apply; managed loading is not certified.' }
                    $expected = @(
                        $marker
                        '$localProfile = Join-Path $env:LOCALAPPDATA ''dotfiles\powershell-profiles\' + $file.Name.Replace("'", "''") + "'"
                        'if (Test-Path -LiteralPath $localProfile -PathType Leaf) { . $localProfile }'
                        ''
                    ) -join "`n"
                    if (($content -replace '\r\n', "`n") -ceq $expected) { New-DotfilesDiagnosticResult Passed 'Managed stub matches its local-copy loading contract.' }
                    else { New-DotfilesDiagnosticResult Drift 'Managed stub differs from its expected loading contract.' }
                }
            }
        }
        if ($scripts -contains 'Install-OmpConfig.ps1') {
            $themeFiles = $null
            try { $themeFiles = @(Get-ChildItem (Join-Path $RepositoryRoot 'poshthemes') -Filter '*.json' -File -ErrorAction Stop) } catch { }
            Add-DotfilesDiagnosticCheck $checks ThemeSource 'Inventory' {
                if (-not $themeFiles) { return New-DotfilesDiagnosticResult Unknown 'Source themes are unavailable or empty.' }
                New-DotfilesDiagnosticResult Passed 'Source theme inventory is readable.'
            }
            foreach ($file in $themeFiles) {
                Add-DotfilesDiagnosticCheck $checks Theme $file.Name {
                    Test-DotfilesDiagnosticFile $file.FullName (Join-Path $UserProfile ".config/oh-my-posh/poshthemes/$($file.Name)")
                }
            }
        }
        if ($scripts -contains 'Install-WindowsTerminalSettings.ps1') {
            Add-DotfilesDiagnosticCheck $checks Terminal 'Settings' {
                $target = Join-Path $LocalAppData 'Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json'
                if (-not (Test-Path -LiteralPath $target -PathType Leaf -ErrorAction Stop)) { return New-DotfilesDiagnosticResult Drift 'Terminal settings file is missing.' }
                # Read failures remain Unknown via the outer wrapper; malformed readable JSON is drift.
                $content = Get-Content -LiteralPath $target -Raw -ErrorAction Stop
                if ([string]::IsNullOrWhiteSpace($content)) { return New-DotfilesDiagnosticResult Drift 'Terminal settings file is empty.' }
                try { $null = ConvertFrom-Json -InputObject $content -ErrorAction Stop }
                catch [System.ArgumentException] { return New-DotfilesDiagnosticResult Drift 'Terminal settings file contains malformed JSON.' }
                New-DotfilesDiagnosticResult Passed 'Settings exist and parse as JSON; local customizations are not compared to the template.'
            }
        }
        # Selected modules without a reliable read-only implementation must never silently pass.
        $covered = @('Configure-WindowsFeatures.ps1', 'Configure-WindowsCapabilities.ps1', 'Install-WingetPackages.ps1', 'Set-EnvironmentVariables.ps1', 'Apply-GitConfig.ps1', 'Install-LocalPowerShellProfiles.ps1', 'Install-OmpConfig.ps1', 'Install-WindowsTerminalSettings.ps1')
        foreach ($module in $preview.Modules) {
            if ($covered -notcontains $module.Script) {
                Add-DotfilesDiagnosticCheck $checks Module $module.Script { New-DotfilesDiagnosticResult Unknown 'This selected module has no installed-state probe yet.' }
            }
        }
        if ($preview.Modules.Count -eq 0) {
            Add-DotfilesDiagnosticCheck $checks Selection 'Modules' { New-DotfilesDiagnosticResult Skipped 'All module selections are empty.' }
        }
    }
    $counts = [ordered]@{}
    foreach ($status in @('Passed', 'Drift', 'Unknown', 'Skipped')) { $counts[$status] = @($checks | Where-Object Status -EQ $status).Count }
    $exitCode = if ($counts.Drift -gt 0) { 1 } elseif ($counts.Unknown -gt 0) { 2 } else { 0 }
    [pscustomobject]@{
        SchemaVersion = 1
        Source = 'Existing local configuration and current invoking user/PowerShell 7 host; no apply or checkout update.'
        Checks = $checks.ToArray()
        Counts = [pscustomobject]$counts
        ExitCode = $exitCode
        Limitations = @('Unknown is not success. A passed probe certifies only the stated check.', 'Profile stubs are checked in the current host profile directory, not every installed PowerShell host.', 'Package queries are opt-in; scope/installer conformance and unsupported modules remain inconclusive.')
    }
}
