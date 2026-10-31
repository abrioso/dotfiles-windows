#Requires -Version 7.2
<#
.SYNOPSIS
Deploys independent, hash-verified Oh My Posh theme copies without elevation.
.DESCRIPTION
Stages theme files beside the destination, verifies their SHA-256 and publishes by rename.
Existing links are migrated even when their contents match. Existing content is backed up
into independent, uniquely named files before replacement. Matching regular files are skipped.
#>
$dotfileRootDir = Split-Path -Parent $PSScriptRoot
. "$dotfileRootDir/setup-scripts/setup-functions.ps1"
. "$dotfileRootDir/setup-scripts/deployment-functions.ps1"

$logFile = Join-Path $dotfileRootDir ('logs/Install-OmpConfig.ps1-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.txt')
Start-Logging -LogFilePath $logFile
try {
    $themeSourceDir = Join-Path $dotfileRootDir 'poshthemes'
    $themeTargetDir = Join-Path $env:USERPROFILE '.config/oh-my-posh/poshthemes'
    $themeFiles = @(Get-ChildItem -LiteralPath $themeSourceDir -Filter '*.json' -File -ErrorAction Stop)
    if ($themeFiles.Count -eq 0) { Write-WarningMessage "No .json theme files found in: $themeSourceDir" }
    foreach ($themeFile in $themeFiles) {
        $result = Copy-DotfilesVerifiedFile -Source $themeFile.FullName -Destination (Join-Path $themeTargetDir $themeFile.Name)
        Write-Info "Theme '$($themeFile.Name)': $($result.Status)."
        if ($result.BackupPath) { Write-Info "Previous theme retained at '$($result.BackupPath)'." }
    }
} catch {
    Write-ErrorMessage "Failed to deploy Oh My Posh themes: $($_.Exception.Message)"
    exit 1
} finally {
    Stop-Logging
}
