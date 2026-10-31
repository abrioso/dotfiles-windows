Describe 'Git-free archive integrity' {
    BeforeAll {
        $repositoryRoot = Split-Path -Parent $PSScriptRoot
        $installer = Join-Path $repositoryRoot 'setup-scripts/install.ps1'
    }
    It 'stops a mismatched download before extraction or setup and removes temporary files' {
        $temp = Join-Path $TestDrive 'downloads'
        New-Item -ItemType Directory $temp | Out-Null
        $previousTemp = $env:TEMP
        $env:TEMP = $temp
        Mock Start-Sleep {}
        Mock Invoke-WebRequest { Set-Content -LiteralPath $OutFile 'unexpected archive bytes' }
        try {
            { & $installer -EndpointType custom-archive -ArchiveUrl 'https://example.invalid/fixture.zip' -ArchiveSha256 ('a' * 64) } | Should -Throw '*SHA-256 mismatch*'
            @(Get-ChildItem (Join-Path $temp 'dotfiles') -Directory) | Should -HaveCount 0
        } finally { $env:TEMP = $previousTemp }
    }
    It 'refuses a commit without a trusted expected archive hash before downloading' {
        Mock Invoke-WebRequest { throw 'Download must not run' }
        { & $installer -Commit ('a' * 40) } | Should -Throw '*requires ArchiveSha256*'
        Should -Invoke Invoke-WebRequest -Times 0 -Exactly
    }
    It 'uses the immutable commit archive and passes the constraint to verified setup' {
        $source = Join-Path $TestDrive 'pinned-source/setup-scripts'
        New-Item -ItemType Directory $source -Force | Out-Null
        @'
param([string]$BootstrapCommit, [string]$BootstrapBranch, [string]$LogFilePath, [switch]$NonInteractive)
Set-Content -LiteralPath (Join-Path $env:TEMP 'received-commit.txt') -Value $BootstrapCommit
& (Join-Path $PSHOME 'pwsh') -NoProfile -Command 'exit 0'
'@ | Set-Content (Join-Path $source 'setup.ps1')
        $archive = Join-Path $TestDrive 'pinned.zip'
        Compress-Archive (Split-Path $source -Parent) $archive
        $hash = (Get-FileHash $archive).Hash
        $temp = Join-Path $TestDrive 'pinned-temp'
        New-Item -ItemType Directory $temp | Out-Null
        $previousTemp = $env:TEMP
        $env:TEMP = $temp
        Mock Start-Sleep {}
        Mock Invoke-WebRequest { Copy-Item $archive $OutFile }
        try {
            & $installer -Commit ('a' * 40) -ArchiveSha256 $hash -NonInteractive
            Get-Content (Join-Path $temp 'received-commit.txt') | Should -Be ('a' * 40)
            Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter { $Uri -eq ('https://github.com/abrioso/dotfiles-windows/archive/' + ('a' * 40) + '.zip') }
        } finally { $env:TEMP = $previousTemp }
    }
}

Describe 'Nerd Font integrity barrier' {
    It 'does not extract or create the fonts directory after a hash mismatch' {
        $repositoryRoot = Split-Path -Parent $PSScriptRoot
        $fixture = Join-Path $TestDrive 'font-fixture'
        New-Item -ItemType Directory "$fixture/setup-scripts", "$fixture/setup-modules", "$fixture/temp", "$fixture/local" -Force | Out-Null
        Copy-Item "$repositoryRoot/setup-modules/Install-NerdFont.ps1" "$fixture/setup-modules/Install-NerdFont.ps1"
        Copy-Item "$repositoryRoot/setup-scripts/downloads.lock.json" "$fixture/setup-scripts/downloads.lock.json"
        @'
function Start-Logging { param($LogFilePath) }
function Stop-Logging {}
function Write-Info { param($Message) }
function Write-ErrorMessage { param($Message) Write-Output $Message }
function Invoke-WebRequest { param($Uri, $OutFile, [switch]$UseBasicParsing) Set-Content $OutFile 'unexpected bytes' }
function Expand-Archive { throw 'Extraction must not run' }
'@ | Set-Content "$fixture/setup-scripts/setup-functions.ps1"
        @'
param([string]$Root)
$env:TEMP = Join-Path $Root 'temp'
$env:LOCALAPPDATA = Join-Path $Root 'local'
& (Join-Path $Root 'setup-modules/Install-NerdFont.ps1')
exit $LASTEXITCODE
'@ | Set-Content "$fixture/run.ps1"
        $output = @(& (Join-Path $PSHOME 'pwsh') -NoProfile -File "$fixture/run.ps1" -Root $fixture 2>&1)
        $LASTEXITCODE | Should -Be 1
        ($output -join "`n") | Should -Match 'SHA-256 mismatch'
        Test-Path "$fixture/local/Microsoft/Windows/Fonts" | Should -BeFalse
        @(Get-ChildItem "$fixture/temp") | Should -HaveCount 0
    }
}
