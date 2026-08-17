<#
.SYNOPSIS
    Safely updates the dotfiles checkout and selected local JSON configuration files.
.DESCRIPTION
    Optionally fast-forward pulls the current repository branch, then discovers every tracked
    *.json.example template. The user chooses which templates replace the corresponding local,
    gitignored *.json files. Existing local files are backed up before atomic replacement.

    This script does not run setup modules, install packages, enable Windows features, or apply
    settings. Shared catalogs are recommended by default; files containing user or machine
    variables remain opt-in.
.EXAMPLE
    .\setup-scripts\update.ps1
.EXAMPLE
    .\setup-scripts\update.ps1 -Tui
.EXAMPLE
    .\setup-scripts\update.ps1 -NonInteractive -UpdateRepository -TemplateName winget-packages.json,windows-features.json
#>
[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$ConfigDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'dotfiles-configurations'),
    [string]$BackupDirectory,
    [string[]]$TemplateName = @(),
    [switch]$Tui,
    [switch]$NonInteractive,
    [switch]$UpdateRepository,
    [switch]$SkipRepositoryUpdate
)

$ErrorActionPreference = 'Stop'
$dotfilesRoot = $RepositoryRoot
. "$PSScriptRoot\update-functions.ps1"

function Read-UpdateConfirmation {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [bool]$Default = $false
    )

    $suffix = if ($Default) { '[Y/n]' } else { '[y/N]' }
    $answer = Read-Host "$Prompt $suffix"
    if ([string]::IsNullOrWhiteSpace($answer)) { return $Default }
    return @('y', 'yes') -contains $answer.Trim().ToLowerInvariant()
}

function Invoke-RepositoryFastForwardUpdate {
    param([Parameter(Mandatory)][string]$RepositoryRoot)

    $gitCommand = @(Get-Command git -CommandType Application -ErrorAction SilentlyContinue)[0]
    if (-not $gitCommand) {
        throw 'Git is required to update the dotfiles repository.'
    }
    $gitExecutable = $gitCommand.Source

    $statusOutput = @(& $gitExecutable -C $RepositoryRoot status --porcelain --untracked-files=no 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "Could not inspect the dotfiles repository:`n$($statusOutput -join "`n")"
    }
    if ($statusOutput.Count -gt 0) {
        throw 'Tracked changes are present. Commit or discard them before updating the dotfiles repository.'
    }

    $branchOutput = @(& $gitExecutable -C $RepositoryRoot rev-parse --abbrev-ref HEAD 2>&1)
    if ($LASTEXITCODE -ne 0 -or $branchOutput.Count -ne 1 -or $branchOutput[0] -eq 'HEAD') {
        throw 'The dotfiles repository must be on a local branch before it can be updated.'
    }
    $branch = [string]$branchOutput[0]

    Write-Host "Fetching origin/$branch..." -ForegroundColor Cyan
    $fetchOutput = @(& $gitExecutable -C $RepositoryRoot fetch origin $branch 2>&1)
    $fetchExitCode = $LASTEXITCODE
    $fetchOutput | Out-Host
    if ($fetchExitCode -ne 0) {
        throw "Failed to fetch origin/$branch."
    }

    Write-Host "Fast-forwarding branch '$branch'..." -ForegroundColor Cyan
    $pullOutput = @(& $gitExecutable -C $RepositoryRoot pull --ff-only origin $branch 2>&1)
    $pullExitCode = $LASTEXITCODE
    $pullOutput | Out-Host
    if ($pullExitCode -ne 0) {
        throw "Failed to fast-forward branch '$branch'. Local history was not rewritten."
    }
}

function Get-TrackedConfigurationTemplatePath {
    param([Parameter(Mandatory)][string]$RepositoryRoot)

    $gitCommand = @(Get-Command git -CommandType Application -ErrorAction SilentlyContinue)[0]
    if (-not $gitCommand) {
        throw 'Git is required to verify tracked configuration templates.'
    }
    $gitExecutable = $gitCommand.Source

    & $gitExecutable -C $RepositoryRoot diff --quiet -- ':(top,glob)dotfiles-configurations/*.json.example'
    if ($LASTEXITCODE -ne 0) {
        throw 'Tracked JSON templates contain unstaged changes. Commit or discard them before using the updater.'
    }
    & $gitExecutable -C $RepositoryRoot diff --cached --quiet -- ':(top,glob)dotfiles-configurations/*.json.example'
    if ($LASTEXITCODE -ne 0) {
        throw 'Tracked JSON templates contain staged changes. Commit or discard them before using the updater.'
    }

    $trackedPaths = @(& $gitExecutable -C $RepositoryRoot ls-files -- ':(top,glob)dotfiles-configurations/*.json.example' 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to enumerate tracked JSON templates:`n$($trackedPaths -join "`n")"
    }

    $configRoot = Get-DotfilesCanonicalPath -Path (Join-Path $RepositoryRoot 'dotfiles-configurations')
    $paths = @($trackedPaths | ForEach-Object {
        $trackedPath = [string]$_
        $fullPath = Get-DotfilesCanonicalPath -Path (Join-Path $RepositoryRoot $trackedPath)
        $parentPath = Get-DotfilesCanonicalPath -Path (Split-Path -Parent $fullPath)
        if (-not $parentPath.Equals($configRoot, (Get-DotfilesPathComparison))) {
            throw "Tracked JSON template is outside the top-level configuration directory: $trackedPath"
        }

        $headHash = @(& $gitExecutable -C $RepositoryRoot rev-parse "HEAD:$trackedPath" 2>&1)
        if ($LASTEXITCODE -ne 0 -or $headHash.Count -ne 1) {
            throw "Failed to resolve the committed Git object for template '$trackedPath'."
        }
        $indexHash = @(& $gitExecutable -C $RepositoryRoot rev-parse ":$trackedPath" 2>&1)
        if ($LASTEXITCODE -ne 0 -or $indexHash.Count -ne 1) {
            throw "Failed to resolve the indexed Git object for template '$trackedPath'."
        }
        $workingHash = @(& $gitExecutable -C $RepositoryRoot hash-object "--path=$trackedPath" $fullPath 2>&1)
        if ($LASTEXITCODE -ne 0 -or $workingHash.Count -ne 1) {
            throw "Failed to hash working template '$trackedPath'."
        }
        if ($headHash[0] -ne $indexHash[0] -or $headHash[0] -ne $workingHash[0]) {
            throw "Tracked JSON template differs from its committed Git object: $trackedPath"
        }
        $fullPath
    })
    if ($paths.Count -eq 0) {
        throw 'No tracked *.json.example templates were found.'
    }
    return $paths
}

function Select-TemplateWithTui {
    param([Parameter(Mandatory)][object[]]$Templates)

    Write-Host ''
    Write-Host '=== JSON template selection ===' -ForegroundColor Cyan
    Write-Host 'Recommended shared catalogs are marked with *. Personalized variables are opt-in.'
    for ($index = 0; $index -lt $Templates.Count; $index++) {
        $marker = if ($Templates[$index].Recommended) { '*' } else { ' ' }
        Write-Host ("  {0,2}) [{1}] {2,-38} {3}" -f ($index + 1), $marker, $Templates[$index].Name, $Templates[$index].Scope)
    }

    $answer = Read-Host "Select comma-separated numbers, 'recommended', 'all', or 'none'"
    if ([string]::IsNullOrWhiteSpace($answer) -or $answer.Trim().ToLowerInvariant() -eq 'recommended') {
        return @($Templates | Where-Object Recommended)
    }
    if ($answer.Trim().ToLowerInvariant() -eq 'all') { return @($Templates) }
    if ($answer.Trim().ToLowerInvariant() -eq 'none') { return @() }

    $selected = [System.Collections.Generic.List[object]]::new()
    foreach ($part in ($answer -split ',')) {
        $number = 0
        if (-not [int]::TryParse($part.Trim(), [ref]$number) -or $number -lt 1 -or $number -gt $Templates.Count) {
            throw "Invalid TUI selection: '$part'."
        }
        $candidate = $Templates[$number - 1]
        if (-not ($selected | Where-Object Name -eq $candidate.Name)) {
            $selected.Add($candidate)
        }
    }
    return $selected.ToArray()
}

if ($UpdateRepository -and $SkipRepositoryUpdate) {
    throw '-UpdateRepository and -SkipRepositoryUpdate cannot be used together.'
}
if ($NonInteractive -and $Tui) {
    throw '-NonInteractive and -Tui cannot be used together.'
}

if ([string]::IsNullOrWhiteSpace($BackupDirectory)) {
    $backupBase = $env:LOCALAPPDATA
    if ([string]::IsNullOrWhiteSpace($backupBase)) {
        $backupRoot = Join-Path ([System.Environment]::GetFolderPath('UserProfile')) '.dotfiles-windows'
    }
    else {
        $backupRoot = Join-Path $backupBase 'dotfiles-windows'
    }
    $backupRoot = Join-Path $backupRoot 'config-backups'
    $BackupDirectory = Join-Path $backupRoot (Get-Date -Format 'yyyyMMdd-HHmmss')
}

Assert-DotfilesUpdaterPathBoundary -RepositoryRoot $dotfilesRoot -ConfigDirectory $ConfigDirectory -BackupDirectory $BackupDirectory

Write-Host 'Dotfiles updater' -ForegroundColor Cyan
Write-Host 'No setup modules will run: packages, Windows features, and settings are not applied by this script.'

$shouldUpdateRepository = $false
if ($NonInteractive) {
    $shouldUpdateRepository = [bool]$UpdateRepository
}
elseif ($UpdateRepository) {
    $shouldUpdateRepository = $true
}
elseif (-not $SkipRepositoryUpdate) {
    $shouldUpdateRepository = Read-UpdateConfirmation -Prompt 'Update the current dotfiles branch with git pull --ff-only?' -Default $true
}

if ($shouldUpdateRepository) {
    Invoke-RepositoryFastForwardUpdate -RepositoryRoot $dotfilesRoot
}
else {
    Write-Host 'Repository update skipped.' -ForegroundColor DarkYellow
}

$trackedTemplatePaths = @(Get-TrackedConfigurationTemplatePath -RepositoryRoot $dotfilesRoot)
$templates = @(Get-DotfilesConfigurationTemplate -ConfigDirectory $ConfigDirectory -AllowedTemplatePath $trackedTemplatePaths)
if ($templates.Count -eq 0) {
    throw "No *.json.example templates were found in '$ConfigDirectory'."
}

$selectedTemplates = @()
if ($NonInteractive) {
    foreach ($name in @($TemplateName)) {
        $candidate = @($templates | Where-Object Name -eq $name)
        if ($candidate.Count -ne 1) {
            throw "Unknown template '$name'. Available names: $($templates.Name -join ', ')."
        }
        $selectedTemplates += $candidate[0]
    }
}
elseif ($Tui) {
    $selectedTemplates = @(Select-TemplateWithTui -Templates $templates)
}
else {
    Write-Host ''
    Write-Host 'Choose local JSON files to refresh from the latest templates.' -ForegroundColor Cyan
    foreach ($template in $templates) {
        $default = [bool]$template.Recommended
        $label = "Replace '$($template.Name)' from its .example template ($($template.Scope))?"
        if (Read-UpdateConfirmation -Prompt $label -Default $default) {
            $selectedTemplates += $template
        }
    }
}

if ($selectedTemplates.Count -eq 0) {
    Write-Host 'No local JSON files selected. Nothing else to do.' -ForegroundColor Green
    return
}

foreach ($template in $selectedTemplates) {
    Assert-DotfilesConfigurationTemplate -TemplatePath $template.TemplatePath
}

Write-Host ''
Write-Host 'Selected replacements:' -ForegroundColor Cyan
$selectedTemplates | ForEach-Object {
    $warning = if ($_.Recommended) { '' } else { ' [contains user/machine variables]' }
    Write-Host "  - $($_.Name)$warning"
}
Write-Host "Existing files will be backed up under: $BackupDirectory"

if (-not $NonInteractive -and -not (Read-UpdateConfirmation -Prompt 'Proceed with these replacements?' -Default $false)) {
    Write-Host 'Replacement cancelled. No local JSON files were changed.' -ForegroundColor DarkYellow
    return
}

$completedResults = [System.Collections.Generic.List[object]]::new()
try {
    foreach ($template in $selectedTemplates) {
        $result = Update-DotfilesConfigurationTemplate -TemplatePath $template.TemplatePath -TargetPath $template.TargetPath -BackupDirectory $BackupDirectory
        $completedResults.Add($result)
    }
}
catch {
    $updateError = $_
    $rollbackErrors = [System.Collections.Generic.List[string]]::new()
    for ($index = $completedResults.Count - 1; $index -ge 0; $index--) {
        try {
            Restore-DotfilesConfigurationTemplate -UpdateResult $completedResults[$index]
        }
        catch {
            $rollbackErrors.Add("$($completedResults[$index].Name): $_")
        }
    }

    if ($rollbackErrors.Count -gt 0) {
        throw "JSON update failed and rollback was incomplete. Original error: $updateError. Rollback errors: $($rollbackErrors -join '; ')"
    }
    throw "JSON update failed; completed replacements were rolled back. $updateError"
}
$results = $completedResults.ToArray()

Write-Host ''
Write-Host 'Update summary' -ForegroundColor Green
foreach ($result in $results) {
    Write-Host ("  - {0}: {1}" -f $result.Name, $result.Status)
    if ($result.BackupPath) {
        Write-Host "      backup: $($result.BackupPath)"
    }
}
Write-Host 'Review the resulting local JSON files before running setup.ps1.' -ForegroundColor Cyan
