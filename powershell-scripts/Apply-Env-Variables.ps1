<#
.SYNOPSIS
Retired setup entry point; stops without changing the machine.
.DESCRIPTION
Review env-variables.json.EnvironmentVariables and invoke setup-modules/Set-EnvironmentVariables.ps1 explicitly.
See powershell-scripts/README.md. No commands are forwarded automatically.
#>

throw 'Retired legacy entry point: Apply-Env-Variables.ps1. Review env-variables.json.EnvironmentVariables and invoke setup-modules/Set-EnvironmentVariables.ps1 explicitly. See powershell-scripts/README.md for migration details.'
