#!/usr/bin/env pwsh
# Quick verifier for the per-machine PowerShell profile deployment

$fail = $false

$expectedOneDrive = Join-Path $env:USERPROFILE 'OneDrive - ISEG\Documents\PowerShell'
$localStore = Join-Path $env:LOCALAPPDATA 'dotfiles\powershell-profiles'
$profileNames = @('Microsoft.PowerShell_profile.ps1', 'Microsoft.VSCode_profile.ps1')

Write-Host "Checking local profile store at $localStore..."

foreach ($name in $profileNames) {
    $p = Join-Path $localStore $name
    if (Test-Path -LiteralPath $p) {
        Write-Host "[OK] $name exists at $p"
    } else {
        Write-Host "[MISSING] $name not found in local store ($p)"
        $fail = $true
    }
}

Write-Host "`nChecking stubs in (possibly OneDrive-synced) profile directory..."

foreach ($name in $profileNames) {
    $stub = Join-Path $expectedOneDrive $name
    if (Test-Path -LiteralPath $stub) {
        $firstLine = Get-Content -LiteralPath $stub -TotalCount 1 -ErrorAction SilentlyContinue
        if ($firstLine -like '*dotfiles-managed stub*') {
            Write-Host "[OK] $stub is a dotfiles-managed stub"
        } else {
            Write-Host "[WARN] $stub exists but is not a dotfiles-managed stub (user-authored?)"
        }
    } else {
        Write-Host "[MISSING] Stub not found at $stub"
        $fail = $true
    }
}

Write-Host "`nChecking current PowerShell profile..."
Write-Host "  $PROFILE"

if (Test-Path -LiteralPath $PROFILE) {
    Write-Host "[OK] Active profile exists at $PROFILE"
    try {
        $preview = Get-Content -LiteralPath $PROFILE -ErrorAction Stop -Raw -Encoding UTF8
        Write-Host "  Preview (first 10 lines):"
        ($preview -split "`n") | Select-Object -First 10 | ForEach-Object { Write-Host "    $_" }
    } catch {
        Write-Host "  [WARN] Unable to read active profile content: $_"
    }
} else {
    Write-Host "[MISSING] Active profile file not found at $PROFILE"
    $fail = $true
}

if ($fail) {
    Write-Host "`nOne or more checks failed."
} else {
    Write-Host "`nAll checks passed."
}

# Build JSON report
$report = [PSCustomObject]@{
    timestamp   = (Get-Date).ToString('o')
    localStore  = $localStore
    checks      = @()
    activeProfile = $null
    allPassed   = -not $fail
}

foreach ($name in $profileNames) {
    $localCopy = Join-Path $localStore $name
    $stub = Join-Path $expectedOneDrive $name
    $report.checks += [PSCustomObject]@{
        name          = $name
        localCopy     = $localCopy
        localExists   = Test-Path -LiteralPath $localCopy
        stub          = $stub
        stubExists    = Test-Path -LiteralPath $stub
        firstLine     = Get-Content -LiteralPath $stub -TotalCount 1 -ErrorAction SilentlyContinue
    }
}

$profileExists = Test-Path -LiteralPath $PROFILE
$profilePreview = @()
if ($profileExists) {
    try {
        $profilePreview = (Get-Content -LiteralPath $PROFILE -ErrorAction Stop -Encoding UTF8) | Select-Object -First 10
    } catch {
        $profilePreview = @()
    }
}

$report.activeProfile = [PSCustomObject]@{
    path = $PROFILE
    exists = $profileExists
    preview = $profilePreview
}

$outFile = Join-Path $PSScriptRoot 'Verify-PowerShellProfiles.results.json'
try {
    $report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $outFile -Encoding UTF8
    Write-Host "JSON report written to $outFile"
} catch {
    Write-Host "[ERROR] Failed to write JSON report: $_"
}

if ($fail) { exit 1 } else { exit 0 }
