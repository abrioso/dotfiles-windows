# Define the URL for the Nerd Font zip file
$nerdFontUrl = "https://github.com/ryanoasis/nerd-fonts/releases/download/v2.1.0/FiraCode.zip"

# Define the path to download the zip file
$zipFilePath = "$env:TEMP\FiraCode.zip"

# Define the path to extract the zip file
$extractPath = "$env:TEMP\FiraCode"

# Define the Windows Fonts directory
$fontsDirectory = "$env:SystemRoot\Fonts"

# Download the Nerd Font zip file
Invoke-WebRequest -Uri $nerdFontUrl -OutFile $zipFilePath

# Extract the zip file
Expand-Archive -Path $zipFilePath -DestinationPath $extractPath

# Copy the font files to the Windows Fonts directory
Get-ChildItem -Path $extractPath -Filter *.ttf | ForEach-Object {
    Copy-Item -Path $_.FullName -Destination $fontsDirectory
}

# Clean up the downloaded and extracted files
Remove-Item -Path $zipFilePath -Force
Remove-Item -Path $extractPath -Recurse -Force

# Refresh the font cache
$shell = New-Object -ComObject Shell.Application
$shell.Namespace(0x14).ParseName("C:\Windows\Fonts").InvokeVerb("Install")