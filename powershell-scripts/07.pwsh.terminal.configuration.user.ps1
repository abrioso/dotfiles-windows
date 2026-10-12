<#
.SYNOPSIS
Retired setup entry point; stops without changing the machine.
.DESCRIPTION
Review base/pwsh setup selections using setup-scripts/setup.ps1 -Plan. Profile deployment is owned by setup-modules/Install-LocalPowerShellProfiles.ps1 and preserves user-authored profiles.
See powershell-scripts/README.md. No commands are forwarded automatically.
#>

throw 'Retired legacy entry point: 07.pwsh.terminal.configuration.user.ps1. Review base/pwsh setup selections using setup-scripts/setup.ps1 -Plan. Profile deployment is owned by setup-modules/Install-LocalPowerShellProfiles.ps1 and preserves user-authored profiles. See powershell-scripts/README.md for migration details.'
