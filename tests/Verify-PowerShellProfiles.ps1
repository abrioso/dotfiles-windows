#Requires -Version 7.2
<#
.SYNOPSIS
Deprecated compatibility entry point for the installed-state diagnostic.
.DESCRIPTION
Delegates to setup-scripts/verify.ps1, including exit codes 0/1/2. This checks all selected
setup components, not just profiles, and requires the existing local configuration.
No profile content, personal paths or report files are exported by this wrapper.
.PARAMETER Format
Text (default) or the canonical versioned Json report. Json output has no deprecation warning.
.PARAMETER CheckPackages
Opt in to the canonical WinGet presence queries and their cache/network behavior.
#>
[CmdletBinding()]
param(
    [ValidateSet('Text', 'Json')][string]$Format = 'Text',
    [switch]$CheckPackages
)

$ErrorActionPreference = 'Stop'
$diagnosticPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'setup-scripts/verify.ps1'
if ($Format -eq 'Text') {
    Write-Warning 'Deprecated: use setup-scripts/verify.ps1. This command now diagnoses all selected setup components and requires existing local configuration.'
}
try {
    & $diagnosticPath @PSBoundParameters
    exit $LASTEXITCODE
} catch {
    Write-Error 'The canonical diagnostic could not run. Use setup-scripts/verify.ps1 from a complete checkout.' -ErrorAction Continue
    exit 1
}
