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

# Check if we are already authenticated with GitHub (gh)
if (-not (gh auth status --hostname "github.com")) {
    # Authenticate GitHub CLI
    Write-Host "Authenticating GitHub CLI..."
    gh auth login
} else {
    Write-Host "Already authenticated with GitHub CLI."
}

# Check if the authentication was successful
if (-not (gh auth status)) {
    Write-Error "GitHub CLI authentication failed. Please try again."
    exit 1
}

# Set up Git global configuration
Write-Host "Setting up Git global configuration..."

# Set the DotFilesRoot and DotfilesConfigFolder variables
# These variables are used to locate the git-variables.json file
$DotfilesRoot = Split-Path -Parent $PSScriptRoot
$DotfilesConfigFolder = Join-Path $DotfilesRoot "dotfiles-configurations"
$GitVariablesFile = Get-ChildItem -Path $DotfilesConfigFolder -Filter "git-variables.json" -ErrorAction Stop

if ($GitVariablesFile) {
    # Set Git global configuration from the git-variables.json file
    Write-Host "Loading Git configuration from $($GitVariablesFile.FullName)"
    $GitVariables = Get-Content -Path $GitVariablesFile.FullName | ConvertFrom-Json
} else {
    throw "The git-variables.json file was not found in $DotfilesConfigFolder"
}

# Validate required configuration values
$requiredGitVars = @("user.name", "user.email")
$missingGitVars = $requiredGitVars | Where-Object { -not $GitVariables.$_ }

if ($missingGitVars) {
    Write-Host "Missing required configuration variables: $($missingGitVars -join ', ')" -ForegroundColor Red
    Exit 1
}

Write-Host "Applying Git global configuration..."
foreach ($key in $GitVariables.PSObject.Properties.Name) {
    Write-Host "Setting Git config: $key = $($GitVariables.$key)"
    git config --global $key $GitVariables.$key
}


Write-Host "Git and GitHub CLI setup complete."