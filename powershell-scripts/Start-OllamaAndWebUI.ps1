<#
.SYNOPSIS
Retired container-recreation entry point; preserves existing containers and volumes.
.DESCRIPTION
Use 13.docker.ollama.user.ps1 with an explicit ComposePath after reviewing the volume
migration instructions in powershell-scripts/README.md. No Docker command is run here.
#>
throw 'Retired unsafe container recreation. Review powershell-scripts/README.md and use 13.docker.ollama.user.ps1 -ComposePath <path>. Existing containers and volumes were not changed.'
