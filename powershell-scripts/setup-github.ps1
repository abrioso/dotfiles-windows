## PowerShell Script to Set Up Git and GitHub CLI
# This script checks for the presence of Git and GitHub CLI, installs them if necessary, and configures them for use.

# Check if GitHub CLI (gh) is installed
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Host "GitHub CLI (gh) is not installed. Installing via winget..."
    winget install --id GitHub.cli -e --source winget
}

# Check if Git is installed
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "Git is not installed. Installing via winget..."
    winget install --id Git.Git -e --source winget
}

# Authenticate GitHub CLI
Write-Host "Authenticating GitHub CLI..."
gh auth login

# Set up Git user configuration
$gitUserName = Read-Host "Enter your Git user name"
$gitUserEmail = Read-Host "Enter your Git email address"

git config --global user.name "$gitUserName"
git config --global user.email "$gitUserEmail"

Write-Host "Git and GitHub CLI setup complete."