<#
.SYNOPSIS
    Interactive configuration TUI for dotfiles-windows.
.DESCRIPTION
    Creates local configuration files from .example templates when missing and lets the user
    edit the common bootstrap, Git, package-group, and endpoint settings before setup runs.
#>
[CmdletBinding()]
param (
    [string]$ConfigDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'dotfiles-configurations'),
    [switch]$NonInteractive,
    [string]$RepositoryRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$dotfilesRoot = Split-Path -Parent $PSScriptRoot
. "$dotfilesRoot\setup-scripts\setup-functions.ps1"

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host "=== $Title ===" -ForegroundColor Cyan
}

function Read-JsonFile {
    param([Parameter(Mandatory)][string]$Path)
    $content = Get-Content -LiteralPath $Path -Raw
    if ([string]::IsNullOrWhiteSpace($content)) { return [pscustomobject]@{} }
    return $content | ConvertFrom-Json
}

function Save-JsonFile {
    param(
        [Parameter(Mandatory)]$Value,
        [Parameter(Mandatory)][string]$Path
    )
    $Value | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Ensure-ConfigFile {
    param([Parameter(Mandatory)][string]$Name)

    $target = Join-Path $ConfigDirectory $Name
    $example = Join-Path $ConfigDirectory "$Name.example"

    if (Test-Path -LiteralPath $target) { return $target }
    if (-not (Test-Path -LiteralPath $example)) { throw "Missing example configuration: $example" }

    Copy-Item -LiteralPath $example -Destination $target -Force
    Write-Host "Created local configuration from template: $Name" -ForegroundColor Green
    return $target
}

function Prompt-Value {
    param(
        [Parameter(Mandatory)][string]$Label,
        [AllowNull()][string]$CurrentValue
    )
    $suffix = if ([string]::IsNullOrWhiteSpace($CurrentValue)) { '' } else { " [$CurrentValue]" }
    $value = Read-Host "$Label$suffix"
    if ([string]::IsNullOrWhiteSpace($value)) { return $CurrentValue }
    return $value.Trim()
}

function Prompt-Choice {
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string[]]$Choices,
        [AllowNull()][string]$CurrentValue
    )

    Write-Host $Label
    for ($i = 0; $i -lt $Choices.Count; $i++) {
        $marker = if ($Choices[$i] -eq $CurrentValue) { '*' } else { ' ' }
        Write-Host ("  {0}) [{1}] {2}" -f ($i + 1), $marker, $Choices[$i])
    }

    $answer = Read-Host "Choose 1-$($Choices.Count) or press Enter to keep current"
    if ([string]::IsNullOrWhiteSpace($answer)) { return $CurrentValue }

    $index = 0
    if ([int]::TryParse($answer, [ref]$index) -and $index -ge 1 -and $index -le $Choices.Count) {
        return $Choices[$index - 1]
    }

    Write-Warning "Invalid choice. Keeping current value: $CurrentValue"
    return $CurrentValue
}

function Prompt-MultiChoice {
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string[]]$Choices,
        [AllowNull()][object[]]$CurrentValues
    )

    $current = @($CurrentValues | Where-Object { $_ })
    Write-Host $Label
    for ($i = 0; $i -lt $Choices.Count; $i++) {
        $marker = if ($current -contains $Choices[$i]) { '*' } else { ' ' }
        Write-Host ("  {0}) [{1}] {2}" -f ($i + 1), $marker, $Choices[$i])
    }

    $answer = Read-Host "Choose comma-separated numbers, 'all', 'none', or Enter to keep current"
    if ([string]::IsNullOrWhiteSpace($answer)) { return $current }
    if ($answer.Trim().ToLowerInvariant() -eq 'all') { return $Choices }
    if ($answer.Trim().ToLowerInvariant() -eq 'none') { return @() }

    $selected = [System.Collections.Generic.List[string]]::new()
    foreach ($part in ($answer -split ',')) {
        $index = 0
        if ([int]::TryParse($part.Trim(), [ref]$index) -and $index -ge 1 -and $index -le $Choices.Count) {
            $choice = $Choices[$index - 1]
            if (-not $selected.Contains($choice)) { $selected.Add($choice) }
        } else {
            Write-Warning "Ignoring invalid selection: $part"
        }
    }
    return $selected.ToArray()
}

$legacyMigration = Get-DotfilesLegacyMigrationState `
    -RepositoryRoot $RepositoryRoot `
    -ConfigDirectory $ConfigDirectory
if ($legacyMigration -and $legacyMigration.Status -eq 'pending') {
    if ($NonInteractive) {
        Write-WarningMessage 'A legacy configuration migration is pending; non-interactive mode will not apply it.'
        Write-Host "Manifest: $($legacyMigration.ManifestPath)"
        Write-Host "Migration directory: $($legacyMigration.MigrationDirectory)"
        Write-Host 'Migration candidates:'
        foreach ($entry in @($legacyMigration.Manifest.candidates)) {
            Write-Host "  - $(Join-Path $legacyMigration.MigrationDirectory $entry.path)"
        }
        foreach ($warning in @($legacyMigration.Manifest.migrationWarnings)) { Write-WarningMessage ([string]$warning) }
        return
    }

    $legacyApply = Invoke-DotfilesLegacyMigrationPrompt -MigrationState $legacyMigration
    if (-not $legacyApply.Applied) { return }
    Write-Host 'Legacy configuration migration applied successfully.' -ForegroundColor Green
}
elseif (-not $legacyMigration) {
    $legacyStage = Invoke-DotfilesLegacyConfigurationStage `
        -RepositoryRoot $RepositoryRoot `
        -ConfigDirectory $ConfigDirectory
    if ($legacyStage.Staged) {
        Write-WarningMessage 'Legacy local configuration was recovered for review; no local configuration files were changed.'
        Write-Host "Migration directory: $($legacyStage.MigrationDirectory)"
        Write-Host "Manifest: $($legacyStage.ManifestPath)"
        Write-Host 'Review the recovered files and run configure again for an explicit apply prompt.'
        return
    }
}

if (-not (Test-Path -LiteralPath $ConfigDirectory)) {
    New-Item -ItemType Directory -Path $ConfigDirectory -Force | Out-Null
}

$configNames = @(
    'dotfiles-bootstrap-variables.json',
    'git-variables.json',
    'env-variables.json',
    'winget-packages.json',
    'windows-features.json',
    'setup-modules.json'
)

foreach ($name in $configNames) { Ensure-ConfigFile -Name $name | Out-Null }

if ($NonInteractive) {
    Write-Host "Configuration files are present. Non-interactive mode requested; skipping prompts."
    return
}

$bootstrapPath = Join-Path $ConfigDirectory 'dotfiles-bootstrap-variables.json'
$gitPath = Join-Path $ConfigDirectory 'git-variables.json'
$wingetPath = Join-Path $ConfigDirectory 'winget-packages.json'
$featuresPath = Join-Path $ConfigDirectory 'windows-features.json'
$setupModulesPath = Join-Path $ConfigDirectory 'setup-modules.json'

$bootstrap = Read-JsonFile -Path $bootstrapPath
$gitConfig = Read-JsonFile -Path $gitPath
$wingetConfig = Read-JsonFile -Path $wingetPath
$featuresConfig = Read-JsonFile -Path $featuresPath
$setupModulesConfig = Read-JsonFile -Path $setupModulesPath

Write-Section 'Repository endpoint'
$endpointTypes = @('github-https', 'github-ssh', 'custom')
$bootstrap.REPOSITORY_ENDPOINT_TYPE = Prompt-Choice -Label 'Endpoint type' -Choices $endpointTypes -CurrentValue $bootstrap.REPOSITORY_ENDPOINT_TYPE
$bootstrap.GITHUB_ACCOUNT = Prompt-Value -Label 'GitHub account' -CurrentValue $bootstrap.GITHUB_ACCOUNT
$bootstrap.GITHUB_DOTFILES_REPO = Prompt-Value -Label 'GitHub repository' -CurrentValue $bootstrap.GITHUB_DOTFILES_REPO
$bootstrap.GITHUB_DOTFILES_BRANCH = Prompt-Value -Label 'GitHub branch for bootstrap downloads' -CurrentValue $bootstrap.GITHUB_DOTFILES_BRANCH
if ($bootstrap.REPOSITORY_ENDPOINT_TYPE -eq 'custom') {
    $bootstrap.CUSTOM_REPOSITORY_URL = Prompt-Value -Label 'Custom repository clone URL' -CurrentValue $bootstrap.CUSTOM_REPOSITORY_URL
}

Write-Section 'Local paths'
$bootstrap.WORKSPACE_FOLDER = Prompt-Value -Label 'Workspace folder under USERPROFILE' -CurrentValue $bootstrap.WORKSPACE_FOLDER

Write-Section 'Package groups'
$packageGroups = @($wingetConfig.PSObject.Properties.Name | Sort-Object)
$bootstrap.INSTALL_PACKAGES = Prompt-MultiChoice -Label 'Package groups to install' -Choices $packageGroups -CurrentValues $bootstrap.INSTALL_PACKAGES

Write-Section 'Windows feature groups'
$featureGroups = if ($featuresConfig) { @($featuresConfig.PSObject.Properties.Name | Sort-Object) } else { @() }
$bootstrap.INSTALL_FEATURES = Prompt-MultiChoice -Label 'Windows feature groups to enable' -Choices $featureGroups -CurrentValues $bootstrap.INSTALL_FEATURES

Write-Section 'Setup setting groups'
$settingGroups = if ($setupModulesConfig.settings) { @($setupModulesConfig.settings.PSObject.Properties.Name | Sort-Object) } else { @() }
$bootstrap.INSTALL_SETTINGS = Prompt-MultiChoice -Label 'Setting groups to apply' -Choices $settingGroups -CurrentValues $bootstrap.INSTALL_SETTINGS

$requiredPackageGroups = Get-DotfilesRequiredPackageGroup -SetupConfig $setupModulesConfig -SelectedSettings $bootstrap.INSTALL_SETTINGS
$selectedPackageGroups = [System.Collections.Generic.List[string]]::new()
foreach ($group in @($bootstrap.INSTALL_PACKAGES)) {
    if (-not [string]::IsNullOrWhiteSpace($group) -and -not $selectedPackageGroups.Contains($group)) {
        $selectedPackageGroups.Add($group)
    }
}
foreach ($requiredGroup in $requiredPackageGroups) {
    if (-not $selectedPackageGroups.Contains($requiredGroup)) {
        Write-Warning "Adding package group '$requiredGroup' because it is required by the selected settings."
        $selectedPackageGroups.Add($requiredGroup)
    }
}
$bootstrap.INSTALL_PACKAGES = $selectedPackageGroups.ToArray()

Write-Section 'Git global config'
$gitConfig.'user.name' = Prompt-Value -Label 'git user.name' -CurrentValue $gitConfig.'user.name'
$gitConfig.'user.email' = Prompt-Value -Label 'git user.email' -CurrentValue $gitConfig.'user.email'
$gitConfig.'core.editor' = Prompt-Value -Label 'git core.editor' -CurrentValue $gitConfig.'core.editor'

Save-JsonFile -Value $bootstrap -Path $bootstrapPath
Save-JsonFile -Value $gitConfig -Path $gitPath

Write-Host ""
Write-Host "Configuration complete." -ForegroundColor Green
Write-Host "Local config files are intentionally gitignored; commit changes only to *.example templates."
