# Equivalent PowerShell script for 2.hyperv.wsl.configuration.admin.dsc.yaml
# Minimum OS version check
# (No MinVersion specified, just check for OS presence)


Function Set-HyperVUserAdmin {
    # Check if the user is an administrator
    $isAdmin = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not $isAdmin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Error "This script must be run as an administrator."
        return
    }

    # Add the current user to the Hyper-V Administrators group
    $user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    Add-LocalGroupMember -Group "Hyper-V Administrators" -Member $user

    try {
        # Try the .NET method first
        try {
            $hyperVGroup = [ADSI]"WinNT://./Hyper-V Administrators,group"
            $members = @($hyperVGroup.Invoke("Members"))
            $isAlreadyMember = $false

            foreach ($member in $members) {
                $memberPath = $member.GetType().InvokeMember("ADsPath", 'GetProperty', $null, $member, $null)
                if ($memberPath -match $currentUserSID) {
                    $isAlreadyMember = $true
                    break
                }
            }

            if (-not $isAlreadyMember) {
                # Using the native NET command as a fallback which works better with Azure AD
                try {
                    $result = net localgroup "Hyper-V Administrators" $username /add
                    Write-Host "Added $username to Hyper-V Administrators group using NET command"
                }
                catch {
                    # Check if the error is "already a member"
                    if ($_.Exception.Message -match "already a member" -or $_.Exception.Message -match "1378") {
                        Write-Host "User is already a member of Hyper-V Administrators group (detected from error)"
                        # Not a real error - this is actually a success condition
                    }
                    else {
                        throw $_
                    }
                }
            } else {
                Write-Host "User is already a member of Hyper-V Administrators group (detected with ADSI)"
            }
        }
        catch {
            Write-Host "First method failed: $_"

            # Fallback to NET command
            try {
                $result = net localgroup "Hyper-V Administrators" $username /add
                Write-Host "Added $username to Hyper-V Administrators group using NET command"
            }
            catch {
                # Check if the error is "already a member"
                if ($_.Exception.Message -match "already a member" -or $_.Exception.Message -match "1378") {
                    Write-Host "User is already a member of Hyper-V Administrators group (detected from error)"
                    # Not a real error - this is actually a success condition
                }
                else {
                    Write-Host "Failed to add user to Hyper-V Administrators: $_"
                    throw $_
                }
            }
        }
    }
    catch {
        # Check if the error is about "already a member"
        if ($_.Exception.Message -match "already a member" -or $_.Exception.Message -match "1378") {
            Write-Host "User is already a member of Hyper-V Administrators group (caught in outer catch)"
            # This is actually a success scenario
        }
        else {
            Write-Host "Error managing Hyper-V Administrators group: $_"
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




# Enable HypervisorPlatform
Enable-WindowsOptionalFeature -Online -FeatureName "HypervisorPlatform" -All -NoRestart

# Enable VirtualMachinePlatform
Enable-WindowsOptionalFeature -Online -FeatureName "VirtualMachinePlatform" -All -NoRestart

# Enable Microsoft-Windows-Subsystem-Linux
Enable-WindowsOptionalFeature -Online -FeatureName "Microsoft-Windows-Subsystem-Linux" -All -NoRestart

# Enable Hyper-V
Enable-WindowsOptionalFeature -Online -FeatureName "Microsoft-Hyper-V-All" -All -NoRestart

# Enable Microsoft-Hyper-V-Tools-All
Enable-WindowsOptionalFeature -Online -FeatureName "Microsoft-Hyper-V-Tools-All" -All -NoRestart

# Set the user as a member of the Hyper-V Administrators group
$useradmin = Set-HyperVUserAdmin
if ($useradmin) {
    Write-Host "User is now a member of Hyper-V Administrators group."
} else {
    Write-Host "User is already a member of Hyper-V Administrators group."
}
