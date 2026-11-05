[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)][string]$ComposePath,
    [ValidatePattern('^[a-z0-9][a-z0-9_-]*$')][string]$ProjectName,
    [ValidateSet('Stop', 'Down', 'Purge')][string]$Action = 'Stop'
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/docker-compose-functions.ps1"
try {
    $composeArguments = @(Get-DotfilesComposeArguments -ComposePath $ComposePath -ProjectName $ProjectName)
    if ($Action -ne 'Purge' -and -not $PSBoundParameters.ContainsKey('Confirm')) { $ConfirmPreference = 'None' }
    $description = if ($Action -eq 'Purge') { 'Remove containers AND persistent models, chats and configuration volumes' } else { $Action }
    if (-not $PSCmdlet.ShouldProcess($ComposePath, $description)) { return }
    [string[]]$operation = if ($Action -eq 'Stop') { @('stop') } else { @('down') }
    if ($Action -eq 'Purge') { $operation += '--volumes' }
    Invoke-DotfilesDocker -Arguments ($composeArguments + $operation)
    Write-Host "Compose operation '$Action' completed successfully."
} catch {
    Write-Error $_ -ErrorAction Continue
    exit 1
}
