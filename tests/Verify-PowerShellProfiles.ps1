#!/usr/bin/env pwsh
# Quick verifier for PowerShell profile symlinks and active profile

$fail = $false

$expectedOneDrive = Join-Path $env:USERPROFILE 'OneDrive - ISEG\Documents\PowerShell'
$checks = @(
    @{ Name = 'Microsoft.PowerShell_profile.ps1'; Path = Join-Path $expectedOneDrive 'Microsoft.PowerShell_profile.ps1' },
    @{ Name = 'Microsoft.VSCode_profile.ps1'; Path = Join-Path $expectedOneDrive 'Microsoft.VSCode_profile.ps1' }
)

Write-Host "Checking PowerShell profile symlinks..."

foreach ($c in $checks) {
    $p = $c.Path
    if (Test-Path -LiteralPath $p) {
        Write-Host "[OK] $($c.Name) exists at $p"
        try {
            $preview = Get-Content -LiteralPath $p -ErrorAction Stop -Raw -Encoding UTF8 -TotalCount 5
            Write-Host "  Preview (first lines):"
            ($preview -split "`n") | Select-Object -First 5 | ForEach-Object { Write-Host "    $_" }
        } catch {
            Write-Host "  [WARN] Unable to read content: $_"
        }
    } else {
        Write-Host "[MISSING] $($c.Name) not found at $p"
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
    timestamp = (Get-Date).ToString('o')
    checks = @()
    activeProfile = $null
    allPassed = -not $fail
}

foreach ($c in $checks) {
    $p = $c.Path
    $exists = Test-Path -LiteralPath $p
    $readable = $false
    $preview = @()
    if ($exists) {
        try {
            $lines = Get-Content -LiteralPath $p -ErrorAction Stop -Encoding UTF8
            $readable = $true
            $preview = $lines | Select-Object -First 5
        } catch {
            $readable = $false
        }
    }
    $report.checks += [PSCustomObject]@{
        name = $c.Name
        path = $p
        exists = $exists
        readable = $readable
        preview = $preview
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
