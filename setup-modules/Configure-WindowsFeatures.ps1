<#
.SYNOPSIS
    Enables optional Windows features required for development.

.DESCRIPTION
    This script enables features like Hyper-V and Windows Subsystem for Linux (WSL).
    It checks if the features are already enabled before attempting to enable them.
    This script requires administrative privileges to run.
    This script is designed to be idempotent.
#>
param (
    [string]$ConfigPath = "$PSScriptRoot/../dotfiles-configurations/windows-features.json",
    [string]$BootstrapPath = "$PSScriptRoot/../dotfiles-configurations/dotfiles-bootstrap-variables.json",
    [string[]]$Groups = @()
)

$dotfilesRoot = Split-Path -Parent $PSScriptRoot
. "$dotfilesRoot\setup-scripts\setup-functions.ps1"

function Test-IsElevated {
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $p = [System.Security.Principal.WindowsPrincipal]::new($id)
    $p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsElevated)) {
    Write-Error "This script requires Administrator privileges to enable Windows features. Please re-run from an elevated PowerShell session."
    exit 1
}

$featuresToEnable = Resolve-DotfilesWindowsFeature -ConfigPath $ConfigPath -BootstrapPath $BootstrapPath -Groups $Groups -GroupsSpecified:$PSBoundParameters.ContainsKey('Groups')

if ($featuresToEnable.Count -eq 0) {
    Write-Output "No Windows feature groups selected. Skipping Windows feature configuration."
    exit 0
}

$restartNeeded = $false

try {
    Write-Host "Checking required Windows features..."

    foreach ($featureName in $featuresToEnable) {
        Write-Host "Processing feature: $featureName"
        $feature = Get-WindowsOptionalFeature -Online -FeatureName $featureName -ErrorAction Stop

        if (-not $feature) {
            throw "Selected Windows feature '$featureName' is not available on this version or edition of Windows."
        }

        if ($feature.State -eq 'Enabled') {
            Write-Host "Feature '$featureName' is already enabled. Skipping."
        } else {
            Write-Host "Feature '$featureName' is currently $($feature.State). Enabling..."
            $result = Enable-WindowsOptionalFeature -Online -FeatureName $featureName -All -NoRestart -ErrorAction Stop

            Write-Host "Successfully enabled feature '$featureName'."
            if ($result.RestartNeeded) {
                $restartNeeded = $true
            }
        }
    }
}
catch {
    Write-Error "An error occurred while enabling Windows features: $_"
    exit 1
}

Write-Host "Windows feature configuration complete."

if ($restartNeeded) {
    Write-Warning "A system restart is required to complete the Windows feature changes. Restart Windows, then re-run setup to continue with packages and settings."
    exit 3010
}
