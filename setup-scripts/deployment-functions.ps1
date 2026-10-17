function Move-DotfilesDeploymentEntry {
    param([string]$Source, [string]$Destination)
    [IO.File]::Move($Source, $Destination, $false)
}

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
    $capturedPath = $null
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
        if ($targetItem) {
            # Capture the actual entry at publication, including any edit made after
            # backup verification. Never overwrite an entry recreated by another writer.
            $capturedPath = $targetPath + '.' + [guid]::NewGuid().ToString('N') + '.captured.bak'
            Move-DotfilesDeploymentEntry $targetPath $capturedPath
        }
        try { Move-DotfilesDeploymentEntry $temporaryPath $targetPath }
        catch {
            $publicationError = $_
            if ($capturedPath) {
                try { Move-DotfilesDeploymentEntry $capturedPath $targetPath }
                catch { throw "Publication failed and the destination could not be restored without overwriting another entry. Previous file retained at '$capturedPath'. Review it before retrying." }
            }
            throw $publicationError
        }
        if ($capturedPath) {
            try {
                # A non-write-sharing handle stabilizes the captured bytes, including
                # legacy hardlink aliases, while preparing an independent backup.
                $capturedStream = [IO.File]::Open($capturedPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
                try {
                    $hasher = [Security.Cryptography.SHA256]::Create()
                    try { $capturedHash = [Convert]::ToHexString($hasher.ComputeHash($capturedStream)) }
                    finally { $hasher.Dispose() }
                    if ($capturedHash -ne $targetHash) {
                        $backupPath = $targetPath + '.' + [guid]::NewGuid().ToString('N') + '.bak'
                        $backupStream = [IO.File]::Open($backupPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
                        try { $capturedStream.Position = 0; $capturedStream.CopyTo($backupStream) }
                        finally { $backupStream.Dispose() }
                        if ((Get-FileHash -LiteralPath $backupPath -Algorithm SHA256 -ErrorAction Stop).Hash -ne $capturedHash) {
                            throw 'Captured backup verification failed.'
                        }
                    }
                } finally { $capturedStream.Dispose() }
                # Delete only after independently retaining the captured content.
                [IO.File]::Delete($capturedPath)
            } catch {
                throw "The new file was published, but captured content could not be independently retained. Previous entry remains at '$capturedPath'. Review it and backups before retrying. $($_.Exception.Message)"
            }
        }
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
