# Equivalent PowerShell script for 07.pwsh.terminal.dsc.configuration.user.dsc.yaml
# Minimum OS version check
# (No MinVersion specified, just check for OS presence)

# Install Windows Terminal
winget install --id Microsoft.WindowsTerminal --accept-source-agreements --accept-package-agreements

# Install PowerShell
winget install --id Powershell.Powershell --accept-source-agreements --accept-package-agreements

# Install Oh My Posh
winget install --id JanDeDobbeleer.OhMyPosh --accept-source-agreements --accept-package-agreements

          $customProfileDirectory = [System.IO.Path]::Combine($env:USERPROFILE, 'PowerShell-Custom')
          # Ensure the directory exists
          if (-not (Test-Path $customProfileDirectory)) {
              New-Item -ItemType Directory -Path $customProfileDirectory | Out-Null
              # Link PowerShell profile to custom directory
              $profilePath = $PROFILE
              $customProfilePath = Join-Path $customProfileDirectory 'Microsoft.PowerShell_profile.ps1'
              if (-not (Test-Path $customProfilePath)) {
                  New-Item -ItemType File -Path $customProfilePath | Out-Null
              }
              if (Test-Path $profilePath) {
                  Remove-Item $profilePath -Force
              }
              New-Item -ItemType SymbolicLink -Path $profilePath -Target $customProfilePath | Out-Null
              Write-Output "Created directory $customProfileDirectory and linked PowerShell profile"

          } else  {
              Write-Output "The directory $customProfileDirectory already exists"
          }