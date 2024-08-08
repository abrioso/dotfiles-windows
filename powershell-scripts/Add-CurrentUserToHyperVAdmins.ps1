# Get the current user's SID
$currentUserSid = ([System.Security.Principal.WindowsIdentity]::GetCurrent()).User.Value

# Get the Hyper-V Administrators group
$hyperVAdminsGroup = Get-LocalGroup -Name "Hyper-V Administrators"

# Add the current user to the Hyper-V Administrators group
Add-LocalGroupMember -Group $hyperVAdminsGroup -Member $currentUserSid