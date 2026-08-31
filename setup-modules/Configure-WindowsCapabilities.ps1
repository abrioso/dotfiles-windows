<#
.SYNOPSIS
    Installs selected Windows capabilities required for development and administration.

.DESCRIPTION
    Resolves capability groups from the local configuration, checks their current state,
    and installs capabilities that are not already installed. This script requires
    administrative privileges and is designed to be idempotent.
#>
param (
    [string]$ConfigPath = "$PSScriptRoot/../dotfiles-configurations/windows-capabilities.json",
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
    $principal = [System.Security.Principal.WindowsPrincipal]::new($id)
    $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

$moduleExitCode = 0
try {
    if (-not (Test-IsElevated)) {
        throw 'This script requires Administrator privileges to install Windows capabilities. Please re-run from an elevated PowerShell session.'
    }

    $capabilitiesToInstall = Resolve-DotfilesWindowsCapability `
        -ConfigPath $ConfigPath `
        -BootstrapPath $BootstrapPath `
        -Groups $Groups `
        -GroupsSpecified:$PSBoundParameters.ContainsKey('Groups')

    if ($capabilitiesToInstall.Count -eq 0) {
        Write-Output 'No Windows capability groups selected. Skipping Windows capability configuration.'
    }
    else {
        $restartNeeded = $false
        Write-Host 'Checking required Windows capabilities...'

        foreach ($capabilityName in $capabilitiesToInstall) {
            Write-Host "Processing capability: $capabilityName"
            $capability = Get-WindowsCapability -Online -Name $capabilityName -ErrorAction Stop

            if (-not $capability) {
                throw "Selected Windows capability '$capabilityName' is not available on this version or edition of Windows."
            }

            if ($capability.State -eq 'Installed') {
                Write-Host "Capability '$capabilityName' is already installed. Skipping."
            }
            elseif ($capability.State -eq 'NotPresent') {
                Write-Host "Capability '$capabilityName' is not present. Installing..."
                $result = Add-WindowsCapability -Online -Name $capabilityName -NoRestart -ErrorAction Stop

                Write-Host "Successfully installed capability '$capabilityName'."
                if ($result.RestartNeeded) {
                    $restartNeeded = $true
                }
            }
            else {
                throw "Selected Windows capability '$capabilityName' has unsupported state '$($capability.State)'."
            }
        }

        Write-Host 'Windows capability configuration complete.'
        if ($restartNeeded) {
            Write-Warning 'A system restart is required to complete the Windows capability changes. Restart Windows, then re-run setup to continue with packages and settings.'
            $moduleExitCode = 3010
        }
    }
}
catch {
    Write-Error "Windows capability configuration failed: $_" -ErrorAction Continue
    $moduleExitCode = 1
}
finally {
    Write-Host "Windows capability module log: $LogFilePath"
    Stop-Logging
}

exit $moduleExitCode
