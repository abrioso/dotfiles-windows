<#
.SYNOPSIS
    Installs the CaskaydiaCove Nerd Font required for the terminal.

.DESCRIPTION
    Downloads and installs the CascadiaCode Nerd Font (CaskaydiaCove) per-user from
    the official nerd-fonts GitHub releases. This font is required for the oh-my-posh
    theme to render correctly in Windows Terminal and other terminals.
    This script is idempotent.

.NOTES
    This script does not require Administrator privileges (installs per-user).
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

$nerdFontUrl    = "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/CascadiaCode.zip"
$zipFilePath    = "$env:TEMP\CascadiaCode.zip"
$extractPath    = "$env:TEMP\CascadiaCode"
$userFontsDir   = "$env:LOCALAPPDATA\Microsoft\Windows\Fonts"
$fontRegistryPath = "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"

# Check if font is already installed (user fonts directory)
$userInstalledFonts = Get-ChildItem -Path $userFontsDir -Filter "*CaskaydiaCove*" -ErrorAction SilentlyContinue
# Check system fonts directory too (installed by another process or admin)
$systemInstalledFonts = Get-ChildItem -Path "$env:SystemRoot\Fonts" -Filter "*CaskaydiaCove*" -ErrorAction SilentlyContinue

if (($userInstalledFonts -and $userInstalledFonts.Count -gt 0) -or ($systemInstalledFonts -and $systemInstalledFonts.Count -gt 0)) {
    Write-Info "CaskaydiaCove Nerd Font is already installed. Skipping."
    Stop-Logging
    Exit 0
}

# Ensure user fonts directory exists
if (-not (Test-Path $userFontsDir)) {
    Write-Info "Creating user fonts directory: $userFontsDir"
    New-Item -ItemType Directory -Path $userFontsDir -Force | Out-Null
}

try {
    Write-Info "Downloading CascadiaCode Nerd Font from $nerdFontUrl..."
    Invoke-WebRequest -Uri $nerdFontUrl -OutFile $zipFilePath -UseBasicParsing

    Write-Info "Extracting font archive..."
    if (Test-Path $extractPath) { Remove-Item $extractPath -Recurse -Force }
    Expand-Archive -Path $zipFilePath -DestinationPath $extractPath -Force

    # Install TTF files, excluding legacy Windows-compatible variants
    $fontFiles = Get-ChildItem -Path $extractPath -Filter "*.ttf" -Recurse |
        Where-Object { $_.Name -notlike "*WindowsCompatible*" }

    if ($fontFiles.Count -eq 0) {
        Write-WarningMessage "No .ttf font files found in the archive."
        Stop-Logging
        Exit 1
    }

    Write-Info "Installing $($fontFiles.Count) font file(s) to $userFontsDir..."
    foreach ($fontFile in $fontFiles) {
        $destPath = Join-Path $userFontsDir $fontFile.Name
        Copy-Item -Path $fontFile.FullName -Destination $destPath -Force

        # Register font in the current-user registry
        $registryName = "$($fontFile.BaseName) (TrueType)"
        New-ItemProperty -Path $fontRegistryPath -Name $registryName -Value $destPath -PropertyType String -Force | Out-Null
        Write-Info "Installed font: $($fontFile.Name)"
    }

    Write-Info "CaskaydiaCove Nerd Font installed successfully."
} catch {
    Write-ErrorMessage "Failed to install CaskaydiaCove Nerd Font: $($_.Exception.Message)"
    Stop-Logging
    Exit 1
} finally {
    # Cleanup temp files
    if (Test-Path $zipFilePath) { Remove-Item $zipFilePath -Force -ErrorAction SilentlyContinue }
    if (Test-Path $extractPath) { Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue }
}

Stop-Logging
