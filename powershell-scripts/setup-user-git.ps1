## PowerShell Script to Set Up Git and GitHub CLI
# This script checks for the presence of Git and GitHub CLI, installs them if necessary, and configures them for use.

# check if winget is installed
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Error "winget is not installed. Please install winget first."
    exit 1
}

# Check if Git is installed
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "Git is not installed. Installing via winget..."
    winget install --id Git.Git -e --source winget
}

# Check if GitHub CLI (gh) is installed
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Host "GitHub CLI (gh) is not installed. Installing via winget..."
    winget install --id GitHub.cli -e --source winget
}


# After installing gh or git, refresh environment variables
$env:PATH = [System.Environment]::GetEnvironmentVariable("PATH","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH","User")

# Authenticate GitHub CLI
Write-Host "Authenticating GitHub CLI..."
gh auth login

# Check if the authentication was successful
if (-not (gh auth status)) {
    Write-Error "GitHub CLI authentication failed. Please try again."
    exit 1
}

# Set up Git global configuration
Write-Host "Setting up Git global configuration..."

# Read dotfiles-configuration git-variables.json file
$gitConfigPath = "$HOME\dotfiles-configuration\git-variables.json"
if (-not (Test-Path $gitConfigPath)) {
    Write-Error "Git configuration file not found at $gitConfigPath. Please ensure it exists."
    exit 1
}
$gitConfig = Get-Content -Path $gitConfigPath | ConvertFrom-Json

foreach ($key in $gitConfig.PSObject.Properties.Name) {
    Write-Host "Setting Git config: $key = $($gitConfig.$key)"
    git config --global $key $gitConfig.$key
}


Write-Host "Git and GitHub CLI setup complete."