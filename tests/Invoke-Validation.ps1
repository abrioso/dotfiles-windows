#Requires -Version 7.2
<#
.SYNOPSIS
Runs the same repository validation locally and in CI.
.DESCRIPTION
Uses pinned development modules, tests all non-ignored PowerShell and JSON files,
and checks whitespace in the working tree, index and optional committed range.
Analyzer warnings are displayed; errors fail validation. Local private JSON is excluded.
.PARAMETER InstallDependencies
Installs missing pinned modules from PSGallery for the current user.
.PARAMETER BaseRef
Checks committed whitespace changes between this Git ref and HEAD, in addition to local changes.
.EXAMPLE
pwsh -NoProfile -File ./tests/Invoke-Validation.ps1 -InstallDependencies
#>
[CmdletBinding()]
param(
    [switch]$InstallDependencies,
    [string]$BaseRef
)

$ErrorActionPreference = 'Stop'
# Native exit statuses are checked below; no-index returns 1 for a clean added file.
$PSNativeCommandUseErrorActionPreference = $false
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$validationModules = [ordered]@{
    Pester = '5.7.1'
    PSScriptAnalyzer = '1.25.0'
}

Push-Location -LiteralPath $repositoryRoot
try {
    foreach ($entry in $validationModules.GetEnumerator()) {
        $module = Get-Module -ListAvailable -Name $entry.Key |
            Where-Object Version -EQ ([version]$entry.Value) | Select-Object -First 1
        if (-not $module -and $InstallDependencies) {
            Install-Module -Name $entry.Key -RequiredVersion $entry.Value -Repository PSGallery -Scope CurrentUser -Force -ErrorAction Stop
            $module = Get-Module -ListAvailable -Name $entry.Key |
                Where-Object Version -EQ ([version]$entry.Value) | Select-Object -First 1
        }
        if (-not $module) {
            throw "Validation requires $($entry.Key) $($entry.Value). Run this script with -InstallDependencies to install pinned development modules."
        }
        Import-Module -Name $module.Path -Force -ErrorAction Stop
        Write-Host "Using $($entry.Key) $($entry.Value)."
    }

    $files = @(git ls-files --cached --others --exclude-standard -- '*.ps1' '*.json' '*.json.example' | Sort-Object -Unique)
    if ($LASTEXITCODE -ne 0) { throw 'Failed to enumerate repository validation files with Git.' }
    $scriptFiles = @($files | Where-Object { $_ -like '*.ps1' })
    $jsonFiles = @($files | Where-Object { $_ -match '\.json(\.example)?$' })
    foreach ($file in $scriptFiles) {
        $tokens = $null
        $parseErrors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile(
            (Join-Path $repositoryRoot $file), [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors.Count -gt 0) {
            throw "PowerShell syntax errors in ${file}: $($parseErrors.Message -join '; ')"
        }
    }
    foreach ($file in $jsonFiles) {
        try { $null = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json -ErrorAction Stop }
        catch { throw "Invalid JSON in ${file}: $($_.Exception.Message)" }
    }
    Write-Host "Parsed $($scriptFiles.Count) PowerShell files and $($jsonFiles.Count) JSON files."

    $diagnostics = @($scriptFiles | ForEach-Object {
        Invoke-ScriptAnalyzer -Path (Join-Path $repositoryRoot $_) -Severity Error, Warning
    })
    if ($diagnostics.Count -gt 0) {
        $diagnostics | Format-Table RuleName, Severity, ScriptName, Line, Message -AutoSize | Out-Host
    }
    $analyzerErrors = @($diagnostics | Where-Object Severity -EQ 'Error')
    $analyzerWarnings = @($diagnostics | Where-Object Severity -EQ 'Warning')
    Write-Host "PSScriptAnalyzer: $($analyzerErrors.Count) errors, $($analyzerWarnings.Count) warnings."
    if ($analyzerErrors.Count -gt 0) { throw 'PSScriptAnalyzer reported errors.' }

    git diff --check
    if ($LASTEXITCODE -ne 0) { throw 'Working-tree whitespace validation failed.' }
    git diff --cached --check
    if ($LASTEXITCODE -ne 0) { throw 'Index whitespace validation failed.' }
    $untrackedFiles = @(git -c core.quotepath=false ls-files --others --exclude-standard)
    if ($LASTEXITCODE -ne 0) { throw 'Failed to enumerate untracked whitespace validation files.' }
    foreach ($file in $untrackedFiles) {
        git diff --no-index --check -- /dev/null $file
        # --no-index implies --exit-code: 1 means added content, 3 includes check errors.
        if ($LASTEXITCODE -notin @(0, 1)) { throw "Untracked-file whitespace validation failed: $file." }
    }
    if (-not [string]::IsNullOrWhiteSpace($BaseRef)) {
        git diff --check $BaseRef HEAD
        if ($LASTEXITCODE -ne 0) { throw "Committed whitespace validation failed for '$BaseRef' through HEAD." }
    }

    $result = Invoke-Pester -Path (Join-Path $repositoryRoot 'tests') -PassThru
    if ($result.FailedCount -gt 0 -or $result.FailedContainersCount -gt 0 -or $result.TotalCount -eq 0) {
        throw "Pester validation failed: $($result.FailedCount) failed tests, $($result.FailedContainersCount) failed containers, $($result.TotalCount) total tests."
    }
    Write-Host "Validation passed: $($result.PassedCount) tests passed, $($result.SkippedCount) skipped."
}
catch {
    Write-Error -Message $_.Exception.Message -ErrorAction Continue
    exit 1
}
finally {
    Pop-Location
}
