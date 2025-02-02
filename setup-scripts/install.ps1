# 
# This is the installer script that downloads the dotfiles repository and runs the setup script.
# 
# The installer script can be run from a PowerShell terminal. It will download the dotfiles repository
# and run the setup script. The setup script is located in the setup-scripts/setup.ps1 file.
# 
# The installer script will download the dotfiles repository from GitHub and extract the contents to
# a temporary folder. The setup script will then be executed from the temporary folder.
#  
# The installer script can be run from a PowerShell terminal by executing the following command:
# 
#   iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/abrioso/dotfiles-windows/main/setup-scripts/install.ps1'))
# 

$ErrorActionPreference = "Stop"

$account = "abrioso"
$repo    = "dotfiles-windows"
$branch  = "main"

$dotfilesTempDir = Join-Path $env:TEMP "dotfiles"
if (![System.IO.Directory]::Exists($dotfilesTempDir)) {[System.IO.Directory]::CreateDirectory($dotfilesTempDir)}
$sourceFile = Join-Path $dotfilesTempDir "dotfiles.zip"
$dotfilesInstallDir = Join-Path $dotfilesTempDir "$repo-$branch"


function Invoke-Download {
  param (
    [string]$url,
    [string]$file
  )
  Write-Host "Downloading $url to $file"
  # wait 5 seconds for the download to start
  Start-Sleep -Seconds 5
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  Invoke-WebRequest -Uri $url -OutFile $file
}

function Expand-Zip {
    param (
        [string]$File,
        [string]$Destination = (Get-Location).Path
    )

    $filePath = Resolve-Path $File
    $destinationPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Destination)
    
    Write-Host "Extract ZIP $File to $Destination"
    # wait 5 seconds before extracting the zip
    Start-Sleep -Seconds 5
    try {
        [System.Reflection.Assembly]::LoadWithPartialName("System.IO.Compression.FileSystem") | Out-Null
        [System.IO.Compression.ZipFile]::ExtractToDirectory("$filePath", "$destinationPath")
    } catch {
        Write-Warning -Message "Unexpected Error. Error details: $_.Exception.Message"
    }
}

Invoke-Download "https://github.com/$account/$repo/archive/$branch.zip" $sourceFile
if ([System.IO.Directory]::Exists($dotfilesInstallDir)) {[System.IO.Directory]::Delete($dotfilesInstallDir, $true)}
Expand-Zip $sourceFile $dotfilesTempDir

Push-Location $dotfilesInstallDir
& .\setup-scripts\setup.ps1
Pop-Location
