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

$newProcess = new-object System.Diagnostics.ProcessStartInfo "PowerShell";
$newProcess.Arguments = "-nologo";
[System.Diagnostics.Process]::Start($newProcess);
exit

