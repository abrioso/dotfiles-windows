[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Import Terminal-Icons module (skip gracefully if not installed)
if (Get-Module -ListAvailable -Name Terminal-Icons) {
    Import-Module -Name Terminal-Icons
}

# Initialise oh-my-posh with the custom theme
$ompConfig = "$env:USERPROFILE\.config\oh-my-posh\poshthemes\jandedobbeleer.omp.json"
if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
    if (Test-Path $ompConfig) {
        oh-my-posh init pwsh --config $ompConfig | Invoke-Expression
    } else {
        Write-Warning "oh-my-posh config not found: $ompConfig`nRun setup-modules\Install-OmpConfig.ps1 (as Administrator) to create the symlink."
    }
}
