##
# This is the installer script that downloads the dotfiles repository and runs the setup script.
# 
# The installer script can be run from a PowerShell terminal. It will download the dotfiles repository
# and run the setup script. The setup script is located in the setup-scripts/setup.ps1 file.
# 
# The installer script will download the dotfiles repository from GitHub and extract the contents to
# a temporary folder. The setup script will then be executed from that temporary folder.
#  
# The installer script can be run from a PowerShell terminal by executing the following command:
# 
#   iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/abrioso/dotfiles-windows/main/setup-scripts/install.ps1'))
# 
##

[CmdletBinding()]
param (
    [string]$Account = "abrioso",
    [string]$Repo = "dotfiles-windows",
    [string]$Branch = "main",
    [ValidateSet("github-archive", "custom-archive")]
    [string]$EndpointType = "github-archive",
    [string]$ArchiveUrl = "",
    [switch]$NonInteractive
)

$ErrorActionPreference = "Stop"

$account = $Account
$repo    = $Repo
$branch  = $Branch

$dotfilesTempDir = Join-Path $env:TEMP "dotfiles"
$invocationDirectory = Join-Path $dotfilesTempDir ([guid]::NewGuid().ToString("N"))
$sourceFile = Join-Path $invocationDirectory "dotfiles.zip"
$folderBranch = $branch -replace '[\\/]', '-'
$localAppData = if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) { $env:TEMP } else { $env:LOCALAPPDATA }
$fallbackLogDirectory = Join-Path $localAppData "dotfiles\logs"
$fallbackLogName = "setup-{0}-{1}.txt" -f (Get-Date -Format "yyyyMMdd-HHmmssfff"), [guid]::NewGuid().ToString("N")
$fallbackLogFile = Join-Path $fallbackLogDirectory $fallbackLogName

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

    $filePath = (Get-Item -LiteralPath $File).FullName
    $destinationPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Destination)
    
    Write-Host "Extract ZIP $File to $Destination"
    # wait 5 seconds before extracting the zip
    Start-Sleep -Seconds 5
    try {
        [System.Reflection.Assembly]::LoadWithPartialName("System.IO.Compression.FileSystem") | Out-Null
        [System.IO.Compression.ZipFile]::ExtractToDirectory("$filePath", "$destinationPath")
    } catch {
        throw "Failed to extract '$File' to '$Destination': $($_.Exception.Message)"
    }
}

function Resolve-ExtractedDotfilesDirectory {
    param (
        [Parameter(Mandatory)]
        [string]$ExpectedDirectory,
        [Parameter(Mandatory)]
        [string]$ExtractionRoot
    )

    if (Test-Path -LiteralPath $ExpectedDirectory) {
        return $ExpectedDirectory
    }

    $candidateDirectories = @(Get-ChildItem -LiteralPath $ExtractionRoot -Directory |
        Sort-Object LastWriteTime -Descending)

    if ($candidateDirectories.Count -eq 1) {
        return $candidateDirectories[0].FullName
    }

    $setupScriptCandidates = @($candidateDirectories |
        Where-Object { Test-Path -LiteralPath (Join-Path (Join-Path $_.FullName "setup-scripts") "setup.ps1") })

    if ($setupScriptCandidates.Count -eq 1) {
        return $setupScriptCandidates[0].FullName
    }

    throw "Could not determine extracted dotfiles directory. Expected '$ExpectedDirectory' or a single extracted folder under '$ExtractionRoot'."
}

if ($EndpointType -eq "custom-archive") {
    if ([string]::IsNullOrWhiteSpace($ArchiveUrl)) { throw "ArchiveUrl is required when EndpointType is custom-archive." }
    $downloadUrl = $ArchiveUrl
} else {
    $downloadUrl = "https://github.com/$account/$repo/archive/$branch.zip"
}

$setupExitCode = 0
try {
    [System.IO.Directory]::CreateDirectory($dotfilesTempDir) | Out-Null
    [System.IO.Directory]::CreateDirectory($invocationDirectory) | Out-Null
    Invoke-Download $downloadUrl $sourceFile

    $dotfilesInstallDir = Join-Path $invocationDirectory "$repo-$folderBranch"
    Expand-Zip $sourceFile $invocationDirectory
    $dotfilesInstallDir = Resolve-ExtractedDotfilesDirectory -ExpectedDirectory $dotfilesInstallDir -ExtractionRoot $invocationDirectory

    Push-Location -LiteralPath $dotfilesInstallDir
    try {
        & .\setup-scripts\setup.ps1 -BootstrapBranch $branch -LogFilePath $fallbackLogFile -NonInteractive:$NonInteractive
        $setupExitCode = $LASTEXITCODE
    } finally {
        Pop-Location
    }
} finally {
    try {
        if ([System.IO.Directory]::Exists($invocationDirectory)) {
            [System.IO.Directory]::Delete($invocationDirectory, $true)
        }
    } catch {
        Write-Warning "Cannot remove temporary installer directory '$invocationDirectory': $($_.Exception.Message)" -WarningAction Continue
    }
}

if ($setupExitCode -ne 0) {
    exit $setupExitCode
}
