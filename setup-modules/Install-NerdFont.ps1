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

function Test-DotfilesNerdFontInstallation {
    param([string]$StatePath, [string]$FontsDirectory, [string]$RegistryPath)
    try {
        if (-not (Test-Path -LiteralPath $StatePath -PathType Leaf)) { return $false }
        $state = Get-Content -LiteralPath $StatePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if ($state.Version -ne 1 -or @($state.Fonts).Count -eq 0) { return $false }
        $registration = Get-ItemProperty -LiteralPath $RegistryPath -ErrorAction Stop
        foreach ($font in $state.Fonts) {
            if ([string]::IsNullOrWhiteSpace($font.Name) -or
                [IO.Path]::GetFileName($font.Name) -ne $font.Name -or
                $font.Name -notlike '*.ttf') { return $false }
            $path = Join-Path $FontsDirectory $font.Name
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $false }
            if ((Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash -ne $font.Hash) { return $false }
            $registryName = '{0} (TrueType)' -f [IO.Path]::GetFileNameWithoutExtension($font.Name)
            if ($registration.$registryName -ne $path) { return $false }
        }
        return $true
    } catch {
        return $false
    }
}

$ErrorActionPreference = 'Stop'
$nerdFontUrl = 'https://github.com/ryanoasis/nerd-fonts/releases/latest/download/CascadiaCode.zip'
$userFontsDir = "$env:LOCALAPPDATA\Microsoft\Windows\Fonts"
$fontRegistryPath = 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
$statePath = Join-Path $userFontsDir 'dotfiles-cascadiacode-state.json'
if (Test-DotfilesNerdFontInstallation -StatePath $statePath -FontsDirectory $userFontsDir -RegistryPath $fontRegistryPath) {
    Write-Info 'CaskaydiaCove Nerd Font files and registration are complete. Skipping.'
    Stop-Logging
    Exit 0
}

# Own only this invocation's temporary files, including concurrent runs.
$invocationDirectory = Join-Path $env:TEMP ('dotfiles-font-' + [guid]::NewGuid().ToString('N'))
$zipFilePath = Join-Path $invocationDirectory 'CascadiaCode.zip'
$extractPath = Join-Path $invocationDirectory 'extracted'

try {
    New-Item -ItemType Directory -Path $invocationDirectory -ErrorAction Stop | Out-Null
    New-Item -ItemType Directory -Path $userFontsDir -Force -ErrorAction Stop | Out-Null
    if (-not (Test-Path -LiteralPath $fontRegistryPath)) {
        New-Item -Path $fontRegistryPath -Force -ErrorAction Stop | Out-Null
    }
    Write-Info "Downloading CascadiaCode Nerd Font from $nerdFontUrl..."
    Invoke-WebRequest -Uri $nerdFontUrl -OutFile $zipFilePath -UseBasicParsing

    Write-Info "Extracting font archive..."
    Expand-Archive -Path $zipFilePath -DestinationPath $extractPath -Force

    # Install TTF files, excluding legacy Windows-compatible variants
    $fontFiles = @(Get-ChildItem -Path $extractPath -Filter "*.ttf" -Recurse |
        Where-Object { $_.Name -notlike "*WindowsCompatible*" })

    if ($fontFiles.Count -eq 0) {
        Write-WarningMessage "No .ttf font files found in the archive."
        Stop-Logging
        Exit 1
    }

    Write-Info "Installing $($fontFiles.Count) font file(s) to $userFontsDir..."
    $installedFonts = @()
    foreach ($fontFile in $fontFiles) {
        $destPath = Join-Path $userFontsDir $fontFile.Name
        Copy-Item -Path $fontFile.FullName -Destination $destPath -Force

        # Register font in the current-user registry
        $registryName = "$($fontFile.BaseName) (TrueType)"
        New-ItemProperty -Path $fontRegistryPath -Name $registryName -Value $destPath -PropertyType String -Force | Out-Null
        $installedFonts += @{ Name = $fontFile.Name; Hash = (Get-FileHash -LiteralPath $destPath -Algorithm SHA256).Hash }
        Write-Info "Installed font: $($fontFile.Name)"
    }

    # Publish completion only after every copy and registry operation succeeds.
    $temporaryState = Join-Path $userFontsDir ('.dotfiles-font-' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        @{ Version = 1; Fonts = $installedFonts } | ConvertTo-Json -Depth 4 |
            Set-Content -LiteralPath $temporaryState -Encoding UTF8
        Move-Item -LiteralPath $temporaryState -Destination $statePath -Force
    } finally {
        if (Test-Path -LiteralPath $temporaryState) { Remove-Item -LiteralPath $temporaryState -Force }
    }
    Write-Info "CaskaydiaCove Nerd Font installed successfully."
} catch {
    Write-ErrorMessage "Failed to install CaskaydiaCove Nerd Font: $($_.Exception.Message)"
    Stop-Logging
    Exit 1
} finally {
    # Cleanup temp files
    if (Test-Path -LiteralPath $invocationDirectory) {
        Remove-Item -LiteralPath $invocationDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Stop-Logging
