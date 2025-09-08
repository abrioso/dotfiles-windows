<#
.SYNOPSIS
    Enables optional Windows features required for development.

.DESCRIPTION
    This script enables features like Hyper-V and Windows Subsystem for Linux (WSL).
    It checks if the features are already enabled before attempting to enable them.
    This script requires administrative privileges to run.
    This script is designed to be idempotent.
#>

function Test-IsElevated {
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $p = [System.Security.Principal.WindowsPrincipal]::new($id)
    $p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsElevated)) {
    Write-Error "This script requires Administrator privileges to enable Windows features. Please re-run from an elevated PowerShell session."
    exit 1
}

$featuresToEnable = @(
    "Microsoft-Hyper-V-All",
    "VirtualMachinePlatform",
    "Microsoft-Windows-Subsystem-Linux"
)

$restartNeeded = $false

try {
    Write-Host "Checking required Windows features..."

    foreach ($featureName in $featuresToEnable) {
        Write-Host "Processing feature: $featureName"
        $feature = Get-WindowsOptionalFeature -Online -FeatureName $featureName -ErrorAction SilentlyContinue

        if (-not $feature) {
            Write-Warning "Could not find feature '$featureName'. It might not be available on this version of Windows. Skipping."
            continue
        }

        if ($feature.State -eq 'Enabled') {
            Write-Host "Feature '$featureName' is already enabled. Skipping."
        } else {
            Write-Host "Feature '$featureName' is currently $($feature.State). Enabling..."
            $result = Enable-WindowsOptionalFeature -Online -FeatureName $featureName -All -NoRestart

            if ($LASTEXITCODE -ne 0) {
                Write-Error "Failed to enable feature '$featureName'."
            } else {
                Write-Host "Successfully enabled feature '$featureName'."
                if ($result.RestartNeeded) {
                    $restartNeeded = $true
                }
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
    Write-Warning "A system restart is required to complete the installation of some features. Please restart your computer."
}
