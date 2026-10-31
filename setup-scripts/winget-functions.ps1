function Invoke-DotfilesWingetQuery {
    param([string]$WingetPath, [string[]]$Arguments)
    # Native stderr is diagnostic data, including on Windows PowerShell hosts.
    $ErrorActionPreference = 'Continue'
    $PSNativeCommandUseErrorActionPreference = $false
    $output = @(& $WingetPath @Arguments 2>&1)
    [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($output -join "`n") }
}

function Get-DotfilesWingetPackageState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Id,
        [string]$Scope,
        [string]$InstallerType,
        [Parameter(Mandatory)][scriptblock]$Query
    )
    $arguments = @('list', '--id', $Id, '--exact', '--source', 'winget', '--disable-interactivity')
    $scopedArguments = $arguments
    if ($Scope) { $scopedArguments += @('--scope', $Scope) }
    $presence = 'Unknown'
    $status = 'Unknown'
    $message = 'WinGet query failed or was inconclusive. Check App Installer, source access and source agreements before retrying.'
    try {
        $result = & $Query $scopedArguments
        # APPINSTALLER_CLI_ERROR_NO_APPLICATIONS_FOUND (0x8A150014), signed/unsigned.
        $notFoundCodes = @(-1978335212, 2316632084)
        $idPattern = '(?im)(?<![\w.-])' + [regex]::Escape($Id) + '(?![\w.-])'
        if ($Scope -eq 'machine' -and $null -ne $result.ExitCode -and $result.ExitCode -in @(-2147024891, 2147942405)) {
            # --scope machine also enumerates all-user MSIX and may require admin.
            # The normal inventory includes machine ARP/fonts plus current-user apps;
            # the user inventory excludes machine ARP/fonts. Their difference can
            # establish machine presence without elevation. Overlap is inconclusive.
            $unscoped = & $Query $arguments
            $userOnly = & $Query ($arguments + @('--scope', 'user'))
            if ($null -ne $userOnly.ExitCode -and $userOnly.ExitCode -in $notFoundCodes) {
                if ($unscoped.ExitCode -eq 0 -and ($unscoped.Output -join "`n") -match $idPattern) {
                    $result = $unscoped
                } elseif ($null -ne $unscoped.ExitCode -and $unscoped.ExitCode -in $notFoundCodes) {
                    return [pscustomobject]@{ Presence = 'Missing'; Status = 'Drift'; Message = 'Package ID was not found in the current-user and machine ARP/font inventory. Other-user MSIX registrations are not assessed.' }
                }
            }
            if ($result.ExitCode -in @(-2147024891, 2147942405)) {
                $message = 'Machine scope could not be distinguished without admin access. Run the diagnostic elevated or review overlapping user/machine installations.'
            }
        }
        if ($result.ExitCode -eq 0 -and ($result.Output -join "`n") -match $idPattern) {
            $presence = 'Present'
            $status = if ($InstallerType) { 'Unknown' } else { 'Passed' }
            $message = if ($InstallerType) {
                'Presence and requested scope matched; the installed installer type cannot be certified by this CLI query.'
            } else { 'Exact package ID and requested scope matched; version is not constrained.' }
        } elseif ($null -ne $result.ExitCode -and $result.ExitCode -in $notFoundCodes) {
            if ($Scope) {
                $unscoped = & $Query $arguments
                if ($unscoped.ExitCode -eq 0 -and ($unscoped.Output -join "`n") -match $idPattern) {
                    $presence = 'ScopeMismatch'
                    $status = 'Drift'
                    $message = 'Package ID was found, but the requested scope did not match. Review and migrate the installation manually; setup will not uninstall or duplicate it.'
                } elseif ($null -ne $unscoped.ExitCode -and $unscoped.ExitCode -in $notFoundCodes) {
                    $presence = 'Missing'
                }
            } else { $presence = 'Missing' }
            if ($presence -eq 'Missing') {
                $status = 'Drift'
                $message = 'Exact package ID was not found by WinGet.'
            }
        }
    } catch {
        # Do not expose raw native output, private paths or exception text in reports.
    }
    [pscustomobject]@{ Presence = $presence; Status = $status; Message = $message }
}
