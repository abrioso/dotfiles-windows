# Get the current user's SID
$currentUserSid = ([System.Security.Principal.WindowsIdentity]::GetCurrent()).User.Value

# Get the Hyper-V Administrators group
$hyperVAdminsGroup = Get-LocalGroup -SID "S-1-5-32-578"

# Add the current user to the Hyper-V Administrators group
Add-LocalGroupMember -Group $hyperVAdminsGroup -Member $currentUserSid