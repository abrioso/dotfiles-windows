[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

#$env:POSH_THEMES_PATH = "C:\Users\AndréKakooBrioso\AppData\Local\Programs\oh-my-posh\themes"
#oh-my-posh init pwsh --config "$env:POSH_THEMES_PATH\jandedobbeleer.omp.json" | Invoke-Expression




# Import Terminal-Icons module
Import-Module -Name Terminal-Icons


#oh-my-posh init pwsh --config "$env:POSH_THEMES_PATH\half-life.omp.json" | Invoke-Expression
#oh-my-posh init pwsh --config "$env:POSH_THEMES_PATH\jandedobbeleer.omp.json" | Invoke-Expression
oh-my-posh init pwsh --config "$env:USERPROFILE\.config\oh-my-posh\poshthemes\jandedobbeleer.omp.json" | Invoke-Expression
