<#
.SYNOPSIS
    Configures and enables HyperV and WSL on Windows.

.DESCRIPTION
    This script configures and enables features like Hyper-V and Windows Subsystem for Linux (WSL).
    It checks if the features are already enabled before attempting to enable them. It also adds the current user to the 'HyperV Admins' group.
    This script requires administrative privileges to run.
    This script is designed to be idempotent.
#>

function Test-IsElevated {
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $p = [System.Security.Principal.WindowsPrincipal]::new($id)
    $p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

Function Set-HyperVUserAdmin {
    $user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

    # Check membership first to stay idempotent
    if (Get-HyperVUserAdmin) {
        Write-Host "User '$user' is already a member of the Hyper-V Administrators group. Skipping."
        return
    }

    try {
        Add-LocalGroupMember -Group "Hyper-V Administrators" -Member $user -ErrorAction Stop
        Write-Host "Added '$user' to Hyper-V Administrators group."
    }
    catch {
        # Error 1378 = "already a member" – treat as success
        if ($_.Exception.Message -match "already a member" -or $_.Exception.HResult -eq -2147023518) {
            Write-Host "User '$user' is already a member of the Hyper-V Administrators group."
        } else {
            Write-Error "Failed to add '$user' to Hyper-V Administrators: $_"
            throw $_
        }
    }
}

Function Get-HyperVUserAdmin {
    # Check if the user is already a member of the Hyper-V Administrators group
    try {
        $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $username = $currentUser.Name

        # Use NET command to check membership
        $groupMembers = net localgroup "Hyper-V Administrators" | Out-String
        return ($groupMembers -match [regex]::Escape($username))
    }
    catch {
        # If we can't determine membership, assume we need to run the script
        return $false
    }
}

if (-not (Test-IsElevated)) {
    Write-Error "This script requires Administrator privileges to enable Windows features. Please re-run from an elevated PowerShell session."
    exit 1
}

$featuresToEnable = @(
    "HypervisorPlatform",
    "VirtualMachinePlatform",
    "Microsoft-Windows-Subsystem-Linux",
    "Microsoft-Hyper-V-All",
    "Microsoft-Hyper-V-Tools-All"
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

# Set the user as a member of the Hyper-V Administrators group
$useradmin = Set-HyperVUserAdmin
if ($useradmin) {
    Write-Host "User is now a member of Hyper-V Administrators group."
} else {
    Write-Host "User is already a member of Hyper-V Administrators group."
}

# Install WSL and Ubuntu if not already installed
try {
    if (-not (Get-Command wsl -ErrorAction SilentlyContinue)) {
        Write-Host "WSL command not found. Please ensure WSL is installed on your system."
    } else {
        $wslDistributions = wsl --list --quiet
        if ($wslDistributions -contains "Ubuntu") {
            Write-Host "Ubuntu distribution is already installed in WSL. Skipping installation."
        } else {
            Write-Host "Installing WSL and Ubuntu distribution..."
            wsl --install --no-distribution
            wsl --install -d Ubuntu
            Write-Host "WSL and Ubuntu installation complete."
        }
    }
}
catch {
    Write-Error "An error occurred while installing WSL or Ubuntu: $_"
}