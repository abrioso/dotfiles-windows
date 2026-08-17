Set-StrictMode -Version Latest

function Remove-DotfilesTemporaryArtifact {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    try {
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
        if ($item) {
            Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
        }
    }
    catch {
        try {
            [System.Console]::Error.WriteLine("Warning: could not remove temporary updater artifact '$Path': $($_.Exception.Message)")
        }
        catch {
            # Cleanup must never mask the replacement or rollback result.
        }
    }
}

function Get-DotfilesCanonicalPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $normalizedInput = $Path.Replace('/', '\')
    if ($normalizedInput.StartsWith('\\?\', [System.StringComparison]::Ordinal) -or $normalizedInput.StartsWith('\\.\', [System.StringComparison]::Ordinal)) {
        throw "Windows device namespace paths are not allowed: $Path"
    }

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $normalizedFullPath = $fullPath.Replace('/', '\')
    if ($normalizedFullPath.StartsWith('\\?\', [System.StringComparison]::Ordinal) -or $normalizedFullPath.StartsWith('\\.\', [System.StringComparison]::Ordinal)) {
        throw "Windows device namespace paths are not allowed: $fullPath"
    }
    return $fullPath
}

function Test-DotfilesPathWithinRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Root
    )

    $fullPath = Get-DotfilesCanonicalPath -Path $Path
    $fullRoot = Get-DotfilesCanonicalPath -Path $Root
    if ($fullPath.Equals($fullRoot, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    $rootPrefix = $fullRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    return $fullPath.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)
}

function Assert-DotfilesPathHasNoReparsePoint {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $current = Get-DotfilesCanonicalPath -Path $Path
    while (-not [string]::IsNullOrWhiteSpace($current)) {
        $item = $null
        try {
            $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
        }
        catch [System.Management.Automation.ItemNotFoundException] {
            $item = $null
        }
        catch {
            throw "Could not inspect updater path component '$current': $_"
        }
        if ($item -and ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Reparse points are not allowed in updater paths: $current"
        }

        $parent = Split-Path -Parent $current
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $current) { break }
        $current = $parent
    }
}

function Assert-DotfilesUpdaterPathBoundary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$ConfigDirectory,
        [Parameter(Mandatory)][string]$BackupDirectory
    )

    $expectedConfig = Join-Path (Get-DotfilesCanonicalPath -Path $RepositoryRoot) 'dotfiles-configurations'
    $actualConfig = Get-DotfilesCanonicalPath -Path $ConfigDirectory
    if (-not $actualConfig.Equals((Get-DotfilesCanonicalPath -Path $expectedConfig), [System.StringComparison]::Ordinal)) {
        throw "Configuration directory must be the repository's dotfiles-configurations directory: $expectedConfig"
    }

    if (Test-DotfilesPathWithinRoot -Path $BackupDirectory -Root $RepositoryRoot) {
        throw 'Backup directory must be outside the dotfiles repository.'
    }

    Assert-DotfilesPathHasNoReparsePoint -Path $RepositoryRoot
    Assert-DotfilesPathHasNoReparsePoint -Path $ConfigDirectory
    Assert-DotfilesPathHasNoReparsePoint -Path $BackupDirectory
}

function Get-DotfilesConfigurationTemplate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ConfigDirectory,

        [Parameter(Mandatory)]
        [string[]]$AllowedTemplatePath
    )

    if (-not (Test-Path -LiteralPath $ConfigDirectory -PathType Container)) {
        throw "Configuration directory not found: $ConfigDirectory"
    }

    $recommendedNames = @(
        'setup-modules.json',
        'windows-features.json',
        'winget-packages.json'
    )

    Get-ChildItem -LiteralPath $ConfigDirectory -Filter '*.json.example' -File |
        Sort-Object Name |
        ForEach-Object {
            $targetName = $_.Name.Substring(0, $_.Name.Length - '.example'.Length)
            $templatePath = Get-DotfilesCanonicalPath -Path $_.FullName
            if ($AllowedTemplatePath -ccontains $templatePath) {
                $isRecommended = $recommendedNames -contains $targetName
                $scope = if ($isRecommended) { 'shared catalog' } else { 'user or machine variables' }

                [pscustomobject]@{
                    Name         = $targetName
                    TemplatePath = $_.FullName
                    TargetPath   = Join-Path $ConfigDirectory $targetName
                    Recommended  = $isRecommended
                    Scope        = $scope
                }
            }
        }
}

function Assert-DotfilesConfigurationTemplate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TemplatePath
    )

    if (-not (Test-Path -LiteralPath $TemplatePath -PathType Leaf)) {
        throw "Configuration template not found: $TemplatePath"
    }

    $templateContent = Get-Content -LiteralPath $TemplatePath -Raw
    try {
        $templateContent | ConvertFrom-Json -ErrorAction Stop | Out-Null
    }
    catch {
        throw "Configuration template is not valid JSON: $TemplatePath. $_"
    }
}

function Update-DotfilesConfigurationTemplate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TemplatePath,

        [Parameter(Mandatory)]
        [string]$TargetPath,

        [Parameter(Mandatory)]
        [string]$BackupDirectory
    )

    Assert-DotfilesPathHasNoReparsePoint -Path $TemplatePath
    Assert-DotfilesPathHasNoReparsePoint -Path $TargetPath
    Assert-DotfilesPathHasNoReparsePoint -Path $BackupDirectory
    Assert-DotfilesConfigurationTemplate -TemplatePath $TemplatePath

    if ((Test-Path -LiteralPath $TargetPath) -and -not (Test-Path -LiteralPath $TargetPath -PathType Leaf)) {
        throw "Local configuration target is not a regular file: $TargetPath"
    }

    $targetExists = Test-Path -LiteralPath $TargetPath -PathType Leaf
    if ($targetExists) {
        $templateHash = (Get-FileHash -LiteralPath $TemplatePath -Algorithm SHA256).Hash
        $targetHash = (Get-FileHash -LiteralPath $TargetPath -Algorithm SHA256).Hash
        if ($templateHash -eq $targetHash) {
            return [pscustomobject]@{
                Name       = Split-Path -Leaf $TargetPath
                Status     = 'Unchanged'
                TargetPath = $TargetPath
                BackupPath = $null
            }
        }
    }

    $backupPath = $null
    if ($targetExists) {
        New-Item -ItemType Directory -Path $BackupDirectory -Force | Out-Null
        Assert-DotfilesPathHasNoReparsePoint -Path $BackupDirectory
        $backupPath = Join-Path $BackupDirectory ("{0}.{1}.bak" -f (Split-Path -Leaf $TargetPath), [System.Guid]::NewGuid().ToString('N'))
        Assert-DotfilesPathHasNoReparsePoint -Path $backupPath
        Copy-Item -LiteralPath $TargetPath -Destination $backupPath -ErrorAction Stop
        Assert-DotfilesPathHasNoReparsePoint -Path $backupPath
    }

    $targetDirectory = Split-Path -Parent $TargetPath
    if (-not (Test-Path -LiteralPath $targetDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null
    }

    $temporaryPath = Join-Path $targetDirectory (".{0}.{1}.tmp" -f (Split-Path -Leaf $TargetPath), [System.Guid]::NewGuid().ToString('N'))
    $replaceBackupPath = Join-Path $targetDirectory (".{0}.{1}.replace-backup" -f (Split-Path -Leaf $TargetPath), [System.Guid]::NewGuid().ToString('N'))
    try {
        Copy-Item -LiteralPath $TemplatePath -Destination $temporaryPath -ErrorAction Stop
        if ($targetExists) {
            [System.IO.File]::Replace($temporaryPath, $TargetPath, $replaceBackupPath)
        }
        else {
            [System.IO.File]::Move($temporaryPath, $TargetPath)
        }
    }
    finally {
        foreach ($cleanupPath in @($temporaryPath, $replaceBackupPath)) {
            Remove-DotfilesTemporaryArtifact -Path $cleanupPath
        }
    }

    [pscustomobject]@{
        Name       = Split-Path -Leaf $TargetPath
        Status     = if ($targetExists) { 'Replaced' } else { 'Created' }
        TargetPath = $TargetPath
        BackupPath = $backupPath
    }
}

function Restore-DotfilesConfigurationTemplate {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$UpdateResult)

    Assert-DotfilesPathHasNoReparsePoint -Path $UpdateResult.TargetPath
    if ($UpdateResult.BackupPath) {
        Assert-DotfilesPathHasNoReparsePoint -Path $UpdateResult.BackupPath
    }

    if ($UpdateResult.Status -eq 'Unchanged') {
        return
    }

    if ($UpdateResult.Status -eq 'Created') {
        if (Test-Path -LiteralPath $UpdateResult.TargetPath -PathType Leaf) {
            Remove-Item -LiteralPath $UpdateResult.TargetPath -Force -ErrorAction Stop
        }
        return
    }

    if ($UpdateResult.Status -ne 'Replaced' -or -not (Test-Path -LiteralPath $UpdateResult.BackupPath -PathType Leaf)) {
        throw "Cannot roll back '$($UpdateResult.Name)' because its backup is unavailable."
    }

    $targetDirectory = Split-Path -Parent $UpdateResult.TargetPath
    $temporaryPath = Join-Path $targetDirectory (".{0}.{1}.rollback" -f $UpdateResult.Name, [System.Guid]::NewGuid().ToString('N'))
    $replaceBackupPath = Join-Path $targetDirectory (".{0}.{1}.rollback-backup" -f $UpdateResult.Name, [System.Guid]::NewGuid().ToString('N'))
    try {
        Copy-Item -LiteralPath $UpdateResult.BackupPath -Destination $temporaryPath -ErrorAction Stop
        [System.IO.File]::Replace($temporaryPath, $UpdateResult.TargetPath, $replaceBackupPath)
    }
    finally {
        foreach ($cleanupPath in @($temporaryPath, $replaceBackupPath)) {
            Remove-DotfilesTemporaryArtifact -Path $cleanupPath
        }
    }
}
