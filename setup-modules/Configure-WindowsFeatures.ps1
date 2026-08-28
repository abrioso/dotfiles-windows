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
    [string[]]$Groups = @(),
    [string]$LogFilePath
)

$dotfilesRoot = Split-Path -Parent $PSScriptRoot
. "$dotfilesRoot\setup-scripts\setup-functions.ps1"

$logPathWasExplicit = $PSBoundParameters.ContainsKey('LogFilePath')
if ([string]::IsNullOrWhiteSpace($LogFilePath)) {
    $dateTime = Get-Date -Format 'yyyyMMdd-HHmmssfff'
    $scriptName = Split-Path -Leaf $PSCommandPath
    $uniqueSuffix = [System.Guid]::NewGuid().ToString('N').Substring(0, 8)
    $LogFilePath = Join-Path $dotfilesRoot "logs/$scriptName-$dateTime-$uniqueSuffix.txt"
}
$LogFilePath = Start-Logging -LogFilePath $LogFilePath -PassThru -RequireRequestedPath:$logPathWasExplicit

function Test-IsElevated {
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $p = [System.Security.Principal.WindowsPrincipal]::new($id)
    $p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

$moduleExitCode = 0
try {
    if (-not (Test-IsElevated)) {
        throw 'This script requires Administrator privileges to enable Windows features. Please re-run from an elevated PowerShell session.'
    }

    $featuresToEnable = Resolve-DotfilesWindowsFeature -ConfigPath $ConfigPath -BootstrapPath $BootstrapPath -Groups $Groups -GroupsSpecified:$PSBoundParameters.ContainsKey('Groups')

    if ($featuresToEnable.Count -eq 0) {
        Write-Output 'No Windows feature groups selected. Skipping Windows feature configuration.'
    } else {
        $restartNeeded = $false
        Write-Host 'Checking required Windows features...'

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

        Write-Host 'Windows feature configuration complete.'
        if ($restartNeeded) {
            Write-Warning 'A system restart is required to complete the Windows feature changes. Restart Windows, then re-run setup to continue with packages and settings.'
            $moduleExitCode = 3010
        }
    }
}
catch {
    Write-Error "Windows feature configuration failed: $_" -ErrorAction Continue
    $moduleExitCode = 1
}
finally {
    Write-Host "Windows feature module log: $LogFilePath"
    Stop-Logging
}

exit $moduleExitCode
