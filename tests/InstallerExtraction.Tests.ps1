Describe 'Git-free installer archive extraction' {
    BeforeAll {
        $script:repositoryRoot = Split-Path -Parent $PSScriptRoot
        $script:installerPath = Join-Path $script:repositoryRoot 'setup-scripts/install.ps1'
    }

    It 'runs a custom archive with a nonstandard root twice' {
        $archiveSource = Join-Path $TestDrive 'archive-source'
        $archiveRoot = Join-Path $archiveSource 'vendor-dotfiles'
        $setupDirectory = Join-Path $archiveRoot 'setup-scripts'
        New-Item -ItemType Directory -Path $setupDirectory -Force | Out-Null
        @'
$invocationFile = Join-Path $env:TEMP 'setup-invocations.txt'
Add-Content -LiteralPath $invocationFile -Value 'invoked'
& (Join-Path $PSHOME 'pwsh') -NoProfile -Command 'exit 0'
'@ | Set-Content -LiteralPath (Join-Path $setupDirectory 'setup.ps1')

        $archivePath = Join-Path $TestDrive 'custom.zip'
        Compress-Archive -Path $archiveRoot -DestinationPath $archivePath
        $installerTemp = Join-Path $TestDrive 'installer-temp'
        New-Item -ItemType Directory -Path $installerTemp | Out-Null
        $previousTemp = $env:TEMP
        $env:TEMP = $installerTemp

        Mock Start-Sleep { }
        Mock Invoke-WebRequest { Copy-Item -LiteralPath $archivePath -Destination $OutFile -Force }

        try {
            & $script:installerPath -EndpointType custom-archive -ArchiveUrl 'https://example.invalid/custom.zip' -NonInteractive
            & $script:installerPath -EndpointType custom-archive -ArchiveUrl 'https://example.invalid/custom.zip' -NonInteractive

            $invocations = @(Get-Content -LiteralPath (Join-Path $installerTemp 'setup-invocations.txt'))
            $invocations.Count | Should -Be 2
            @(Get-ChildItem -LiteralPath (Join-Path $installerTemp 'dotfiles') -Directory).Count | Should -Be 0
        }
        finally {
            $env:TEMP = $previousTemp
        }
    }

    It 'isolates archives for overlapping installer invocations' {
        $firstArchiveSource = Join-Path $TestDrive 'first-archive-source'
        $firstArchiveRoot = Join-Path $firstArchiveSource 'first-vendor-root'
        $firstSetupDirectory = Join-Path $firstArchiveRoot 'setup-scripts'
        New-Item -ItemType Directory -Path $firstSetupDirectory -Force | Out-Null
        @'
Add-Content -LiteralPath (Join-Path $env:TEMP 'archive-invocations.txt') -Value 'first'
& (Join-Path $PSHOME 'pwsh') -NoProfile -Command 'exit 0'
'@ | Set-Content -LiteralPath (Join-Path $firstSetupDirectory 'setup.ps1')

        $secondArchiveSource = Join-Path $TestDrive 'second-archive-source'
        $secondArchiveRoot = Join-Path $secondArchiveSource 'second-vendor-root'
        $secondSetupDirectory = Join-Path $secondArchiveRoot 'setup-scripts'
        New-Item -ItemType Directory -Path $secondSetupDirectory -Force | Out-Null
        @'
Add-Content -LiteralPath (Join-Path $env:TEMP 'archive-invocations.txt') -Value 'second'
& (Join-Path $PSHOME 'pwsh') -NoProfile -Command 'exit 0'
'@ | Set-Content -LiteralPath (Join-Path $secondSetupDirectory 'setup.ps1')

        $firstArchivePath = Join-Path $TestDrive 'first.zip'
        $secondArchivePath = Join-Path $TestDrive 'second.zip'
        Compress-Archive -Path $firstArchiveRoot -DestinationPath $firstArchivePath
        Compress-Archive -Path $secondArchiveRoot -DestinationPath $secondArchivePath
        $installerTemp = Join-Path $TestDrive 'overlapping-installer-temp'
        $dotfilesTemp = Join-Path $installerTemp 'dotfiles'
        $unrelatedDirectory = Join-Path $dotfilesTemp 'keep-me'
        New-Item -ItemType Directory -Path $unrelatedDirectory -Force | Out-Null
        $previousTemp = $env:TEMP
        $env:TEMP = $installerTemp
        $downloadDestinations = [System.Collections.Generic.List[string]]::new()
        $downloadCount = 0
        $installerPath = $script:installerPath

        Mock Start-Sleep { }
        Mock Invoke-WebRequest {
            $downloadCount++
            $downloadDestinations.Add($OutFile)
            if ($downloadCount -eq 1) {
                Copy-Item -LiteralPath $firstArchivePath -Destination $OutFile -Force
                & $installerPath -EndpointType custom-archive -ArchiveUrl 'https://example.invalid/second.zip' -NonInteractive
            }
            else {
                Copy-Item -LiteralPath $secondArchivePath -Destination $OutFile -Force
            }
        }

        try {
            & $script:installerPath -EndpointType custom-archive -ArchiveUrl 'https://example.invalid/first.zip' -NonInteractive

            @(Get-Content -LiteralPath (Join-Path $installerTemp 'archive-invocations.txt')) | Should -Be @('second', 'first')
            $downloadDestinations.Count | Should -Be 2
            (Split-Path -Parent $downloadDestinations[0]) | Should -Not -Be (Split-Path -Parent $downloadDestinations[1])
            foreach ($downloadDestination in $downloadDestinations) {
                [guid]::Parse((Split-Path -Leaf (Split-Path -Parent $downloadDestination))) | Should -Not -Be ([guid]::Empty)
            }
            Test-Path -LiteralPath $unrelatedDirectory -PathType Container | Should -BeTrue
            @(Get-ChildItem -LiteralPath $dotfilesTemp -Directory).Count | Should -Be 1
        }
        finally {
            $env:TEMP = $previousTemp
        }
    }

    It 'keeps resolving the expected GitHub archive root' {
        $archiveSource = Join-Path $TestDrive 'github-archive-source'
        $archiveRoot = Join-Path $archiveSource 'dotfiles-windows-main'
        $setupDirectory = Join-Path $archiveRoot 'setup-scripts'
        New-Item -ItemType Directory -Path $setupDirectory -Force | Out-Null
        @'
Set-Content -LiteralPath (Join-Path $env:TEMP 'github-setup-ran.txt') -Value 'invoked'
& (Join-Path $PSHOME 'pwsh') -NoProfile -Command 'exit 0'
'@ | Set-Content -LiteralPath (Join-Path $setupDirectory 'setup.ps1')

        $archivePath = Join-Path $TestDrive 'github.zip'
        Compress-Archive -Path $archiveRoot -DestinationPath $archivePath
        $installerTemp = Join-Path $TestDrive 'github-installer-temp'
        New-Item -ItemType Directory -Path $installerTemp | Out-Null
        $previousTemp = $env:TEMP
        $env:TEMP = $installerTemp

        Mock Start-Sleep { }
        Mock Invoke-WebRequest { Copy-Item -LiteralPath $archivePath -Destination $OutFile -Force }

        try {
            & $script:installerPath -NonInteractive

            Get-Content -LiteralPath (Join-Path $installerTemp 'github-setup-ran.txt') | Should -Be 'invoked'
            @(Get-ChildItem -LiteralPath (Join-Path $installerTemp 'dotfiles') -Directory).Count | Should -Be 0
        }
        finally {
            $env:TEMP = $previousTemp
        }
    }

    It 'removes only its isolated extraction directory when extraction fails' {
        $invalidArchive = Join-Path $TestDrive 'invalid.zip'
        Set-Content -LiteralPath $invalidArchive -Value 'not a zip archive'
        $installerTemp = Join-Path $TestDrive 'failed-installer-temp'
        $dotfilesTemp = Join-Path $installerTemp 'dotfiles'
        $unrelatedDirectory = Join-Path $dotfilesTemp 'keep-me'
        New-Item -ItemType Directory -Path $unrelatedDirectory -Force | Out-Null
        $previousTemp = $env:TEMP
        $env:TEMP = $installerTemp

        Mock Start-Sleep { }
        Mock Invoke-WebRequest { Copy-Item -LiteralPath $invalidArchive -Destination $OutFile -Force }

        try {
            { & $script:installerPath -EndpointType custom-archive -ArchiveUrl 'https://example.invalid/invalid.zip' -NonInteractive } |
                Should -Throw -ExpectedMessage "Failed to extract*"
            Test-Path -LiteralPath $unrelatedDirectory -PathType Container | Should -BeTrue
            @(Get-ChildItem -LiteralPath $dotfilesTemp -Directory).Count | Should -Be 1
        }
        finally {
            $env:TEMP = $previousTemp
        }
    }
}
