function Copy-DotfilesVerifiedFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination
    )
    $sourcePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Source)
    $targetPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Destination)
    if ($sourcePath.Equals($targetPath, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Deployment source and destination must be different paths.'
    }
    $sourceItem = Get-Item -LiteralPath $sourcePath -Force -ErrorAction Stop
    if ($sourceItem.PSIsContainer) { throw 'Deployment source must be a file.' }
    $parent = Split-Path -Parent $targetPath
    # A linked directory could redirect publication into the checkout itself.
    $component = $parent
    while ($component) {
        $directory = $null
        try { $directory = Get-Item -LiteralPath $component -Force -ErrorAction Stop }
        catch [System.Management.Automation.ItemNotFoundException] { }
        if ($directory -and ($directory.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "Deployment directory is a link or junction. Review it before retrying: $component"
        }
        $next = Split-Path -Parent $component
        if ($next -eq $component) { break }
        $component = $next
    }
    $sourceHash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256 -ErrorAction Stop).Hash
    $targetItem = $null
    try { $targetItem = Get-Item -LiteralPath $targetPath -Force -ErrorAction Stop }
    catch [System.Management.Automation.ItemNotFoundException] { }
    $targetHash = $null
    if ($targetItem) {
        if ($targetItem.PSIsContainer) { throw 'Deployment destination is a directory; review it before retrying.' }
        $targetHash = (Get-FileHash -LiteralPath $targetPath -Algorithm SHA256 -ErrorAction Stop).Hash
        $isLinked = $targetItem.LinkType -or ($targetItem.Attributes -band [IO.FileAttributes]::ReparsePoint)
        if ($targetHash -eq $sourceHash -and -not $isLinked) {
            return [pscustomobject]@{ Status = 'Unchanged'; BackupPath = $null }
        }
    }
    [IO.Directory]::CreateDirectory($parent) | Out-Null
    $temporaryPath = Join-Path $parent ('.dotfiles-deploy-' + [guid]::NewGuid().ToString('N') + '.tmp')
    $backupPath = $null
    try {
        Copy-Item -LiteralPath $sourcePath -Destination $temporaryPath -ErrorAction Stop
        if ((Get-FileHash -LiteralPath $temporaryPath -Algorithm SHA256 -ErrorAction Stop).Hash -ne $sourceHash -or
            (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256 -ErrorAction Stop).Hash -ne $sourceHash) {
            throw 'Deployment copy verification failed or the source changed. The destination was not replaced.'
        }
        if ($targetItem) {
            if ((Get-FileHash -LiteralPath $targetPath -Algorithm SHA256 -ErrorAction Stop).Hash -ne $targetHash) {
                throw 'Deployment destination changed during staging. Review it and retry.'
            }
            $backupPath = $targetPath + '.' + [guid]::NewGuid().ToString('N') + '.bak'
            # Copy bytes into a new file; never preserve a legacy link in the backup.
            [IO.File]::Copy($targetPath, $backupPath, $false)
            if ((Get-FileHash -LiteralPath $backupPath -Algorithm SHA256 -ErrorAction Stop).Hash -ne $targetHash) {
                throw 'Deployment backup verification failed. The destination was not replaced.'
            }
        }
        # Stage beside the destination, so publication is a same-volume rename.
        # Replace the directory entry rather than writing through an existing link.
        [IO.File]::Move($temporaryPath, $targetPath, [bool]$targetItem)
        if ((Get-FileHash -LiteralPath $targetPath -Algorithm SHA256 -ErrorAction Stop).Hash -ne $sourceHash) {
            throw "Published file verification failed. Review the destination and retained backup: $backupPath"
        }
        [pscustomobject]@{ Status = if ($targetItem) { 'Replaced' } else { 'Created' }; BackupPath = $backupPath }
    } finally {
        if ([IO.File]::Exists($temporaryPath)) {
            try { [IO.File]::Delete($temporaryPath) }
            catch { Write-Warning "Could not remove deployment staging file '$temporaryPath'." -WarningAction Continue }
        }
    }
}
