#Requires -Version 7.2
<#
.SYNOPSIS
Diagnoses the invoked checkout's selected setup state without applying configuration.
.PARAMETER Format
Text (default) or Json output. No report or transcript is written automatically.
.PARAMETER CheckPackages
Opt in to WinGet presence queries. WinGet may access sources and write its own cache/logs.
No source agreements are accepted and no packages are installed or updated.
.NOTES
Exit 0: passed/skipped only; 1: detected drift; 2: inconclusive or invalid configuration.
#>
[CmdletBinding()]
param(
    [ValidateSet('Text', 'Json')][string]$Format = 'Text',
    [switch]$CheckPackages
)

. "$PSScriptRoot/setup-functions.ps1"
. "$PSScriptRoot/setup-plan.ps1"
. "$PSScriptRoot/verify-functions.ps1"
$report = Get-DotfilesSetupDiagnostic -RepositoryRoot (Split-Path -Parent $PSScriptRoot) -CheckPackages:$CheckPackages
if ($Format -eq 'Json') {
    $report | ConvertTo-Json -Depth 8
} else {
    foreach ($check in $report.Checks) {
        Write-Host "[$($check.Status)] $($check.Category) / $($check.Name): $($check.Message)"
    }
    Write-Host "Passed=$($report.Counts.Passed) Drift=$($report.Counts.Drift) Unknown=$($report.Counts.Unknown) Skipped=$($report.Counts.Skipped)"
}
exit $report.ExitCode
