<#
.SYNOPSIS
Links the oh-my-posh theme configuration files without requiring elevation.

.DESCRIPTION
This script creates the ~/.config/oh-my-posh/poshthemes/ directory and hard-links each
tracked theme into it. Hard links preserve the version-controlled single source of truth
without requiring Developer Mode or Administrator privileges. If the repository and profile
are on different volumes, the script falls back to a regular copy. This script is idempotent.

.NOTES
This script is intended to be run from the root of the dotfiles repository.
#>

# dotfileRootDir is the root directory of the dotfiles repository
$dotfileRootDir = Split-Path -Parent $PSScriptRoot

. "$dotfileRootDir\setup-scripts\setup-functions.ps1"

# Variables for logging
$dateTime = Get-Date -Format "yyyyMMdd-HHmmss"
$logDir = Join-Path $dotfileRootDir "logs"
$scriptName = Split-Path -Leaf $PSCommandPath
$logFile = "$logDir/$scriptName-$dateTime.txt"

# Start logging
Start-Logging -LogFilePath $logFile

$themeSourceDir = Join-Path $dotfileRootDir "poshthemes"
$themeTargetDir = Join-Path $env:USERPROFILE ".config\oh-my-posh\poshthemes"

if (-not (Test-Path $themeSourceDir)) {
    Write-ErrorMessage "Poshthemes source directory not found: $themeSourceDir"
    Stop-Logging
    Exit 1
}

# Ensure the target directory exists
if (-not (Test-Path $themeTargetDir)) {
    Write-Info "Creating oh-my-posh config directory: $themeTargetDir"
    New-Item -ItemType Directory -Path $themeTargetDir -Force | Out-Null
}

$themeFiles = Get-ChildItem -Path $themeSourceDir -Filter "*.json"
if ($themeFiles.Count -eq 0) {
    Write-WarningMessage "No .json theme files found in: $themeSourceDir"
} else {
    foreach ($themeFile in $themeFiles) {
        $targetPath = Join-Path $themeTargetDir $themeFile.Name

        if (Test-Path $targetPath) {
            $existingItem = Get-Item $targetPath -Force
            if ($existingItem.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                if ($existingItem.Target -eq $themeFile.FullName) {
                    Write-Info "Symlink for '$($themeFile.Name)' is already correct. Skipping."
                    continue
                } else {
                    Write-Info "Updating stale symlink for '$($themeFile.Name)'..."
                    Remove-Item $targetPath -Force
                }
            } else {
                $sourceHash = (Get-FileHash -LiteralPath $themeFile.FullName -Algorithm SHA256).Hash
                $targetHash = (Get-FileHash -LiteralPath $targetPath -Algorithm SHA256).Hash
                if ($sourceHash -eq $targetHash) {
                    Write-Info "Theme '$($themeFile.Name)' is already deployed. Skipping."
                    continue
                }

                $backupPath = "$targetPath.bak"
                Write-Info "Theme '$($themeFile.Name)' has changed; backing up existing file to '$backupPath' and replacing it."
                Copy-Item -LiteralPath $targetPath -Destination $backupPath -Force
                Remove-Item $targetPath -Force
            }
        }

        Write-Info "Creating hard link: $targetPath -> $($themeFile.FullName)"
        try {
            New-Item -ItemType HardLink -Path $targetPath -Value $themeFile.FullName -ErrorAction Stop | Out-Null
            Write-Info "Hard link created for '$($themeFile.Name)'."
        } catch {
            Write-WarningMessage "Could not create a hard link for '$($themeFile.Name)': $($_.Exception.Message)"
            Write-WarningMessage "Copying the theme because the source and target may be on different volumes."
            try {
                Copy-Item -LiteralPath $themeFile.FullName -Destination $targetPath -ErrorAction Stop
                Write-Info "Theme copied for '$($themeFile.Name)'."
            } catch {
                Write-ErrorMessage "Failed to deploy theme '$($themeFile.Name)': $($_.Exception.Message)"
                Stop-Logging
                Exit 1
            }
        }
    }
}

Stop-Logging
