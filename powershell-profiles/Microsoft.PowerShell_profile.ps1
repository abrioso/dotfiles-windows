[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
#$env:POSH_THEMES_PATH = "C:\Users\AndréKakooBrioso\AppData\Local\Programs\oh-my-posh\themes"
#oh-my-posh init pwsh --config "$env:POSH_THEMES_PATH\jandedobbeleer.omp.json" | Invoke-Expression


# Import the Posh-Git module
#Import-Module -Name Posh-Git

# Import the PSReadLine module
#Import-Module -Name PSReadLine


# Import Terminal-Icons module
Import-Module -Name Terminal-Icons

# Customize your prompt by modifying the $DefaultUser variable
$DefaultUser = "akbrioso"

# Add any additional customizations or aliases here

# Set the prompt
function prompt {
    $prompt = Get-PoshPrompt
    $prompt.User = $DefaultUser
    $prompt.BeforeText = " "
    $prompt.AfterText = " "
    $prompt
}

oh-my-posh init pwsh --config "$env:POSH_THEMES_PATH\half-life.omp.json" | Invoke-Expression
