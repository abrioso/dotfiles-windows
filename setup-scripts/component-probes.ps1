function Get-DotfilesFontDiagnostic {
    param([string]$RepositoryRoot, [string]$LocalAppData)
    $lock = Get-Content -LiteralPath (Join-Path $RepositoryRoot 'setup-scripts/downloads.lock.json') -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if ($lock.Version -ne 1 -or $lock.CascadiaCode.Sha256 -notmatch '^[a-fA-F0-9]{64}$') {
        return New-DotfilesDiagnosticResult Unknown 'Font download lock is invalid.'
    }
    $directory = Join-Path $LocalAppData 'Microsoft/Windows/Fonts'
    $statePath = Join-Path $directory 'dotfiles-cascadiacode-state.json'
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf -ErrorAction Stop)) {
        return New-DotfilesDiagnosticResult Drift 'Font completion record is missing; reapply font setup.'
    }
    $content = Get-Content -LiteralPath $statePath -Raw -ErrorAction Stop
    try { $state = $content | ConvertFrom-Json -ErrorAction Stop }
    catch { return New-DotfilesDiagnosticResult Drift 'Font completion record is malformed.' }
    if ($state.Version -ne 1 -or @($state.Fonts).Count -eq 0 -or
        $state.Release -ne $lock.CascadiaCode.Release -or $state.ArchiveSha256 -ne $lock.CascadiaCode.Sha256) {
        return New-DotfilesDiagnosticResult Drift 'Font completion record does not match the current download lock.'
    }
    $registry = 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
    if (-not (Test-Path -LiteralPath $registry -ErrorAction Stop)) {
        return New-DotfilesDiagnosticResult Drift 'Per-user font registration is missing.'
    }
    $registration = Get-ItemProperty -LiteralPath $registry -ErrorAction Stop
    foreach ($font in $state.Fonts) {
        if ([string]::IsNullOrWhiteSpace($font.Name) -or $font.Name -match '[\\/]' -or
            $font.Name -notlike '*.ttf' -or $font.Hash -notmatch '^[a-fA-F0-9]{64}$') {
            return New-DotfilesDiagnosticResult Drift 'Font completion record contains invalid entries.'
        }
        $path = Join-Path $directory $font.Name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf -ErrorAction Stop) -or
            (Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash -ne $font.Hash) {
            return New-DotfilesDiagnosticResult Drift 'A recorded font file is missing or differs from its installed hash.'
        }
        $name = '{0} (TrueType)' -f [IO.Path]::GetFileNameWithoutExtension($font.Name)
        if ($registration.$name -ne $path) {
            return New-DotfilesDiagnosticResult Drift 'A recorded font is not registered at its expected per-user path.'
        }
    }
    New-DotfilesDiagnosticResult Passed 'Recorded font files, hashes, registration and release match. Local completion metadata is the inventory source.'
}

function Get-DotfilesWslDefaultDiagnostic {
    $state = Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss' -ErrorAction Stop
    if ($null -eq $state.DefaultVersion) { return New-DotfilesDiagnosticResult Unknown 'WSL default version is not recorded.' }
    if ($state.DefaultVersion -eq 2) { return New-DotfilesDiagnosticResult Passed 'New distributions default to WSL 2.' }
    if ($state.DefaultVersion -eq 1) { return New-DotfilesDiagnosticResult Drift 'New distributions default to WSL 1.' }
    New-DotfilesDiagnosticResult Unknown 'WSL default version is not recognized.'
}

function Get-DotfilesWslDistributionDiagnostic {
    $names = Invoke-DotfilesDiagnosticNative 'wsl.exe' @('--list', '--quiet')
    if ($names.ExitCode -ne 0) { return New-DotfilesDiagnosticResult Unknown 'WSL distribution inventory could not be read.' }
    $registered = @(($names.Output -replace "`0", '') -split '\r?\n' | ForEach-Object { $_.Trim() })
    if ($registered -notcontains 'Ubuntu') { return New-DotfilesDiagnosticResult Skipped 'Ubuntu is not registered yet; first launch remains a user action.' }
    $query = Invoke-DotfilesDiagnosticNative 'wsl.exe' @('--list', '--verbose')
    if ($query.ExitCode -ne 0) { return New-DotfilesDiagnosticResult Unknown 'WSL distribution versions could not be read.' }
    $lines = @(($query.Output -replace "`0", '') -split '\r?\n' | Where-Object { $_ -match '^\s*\*?\s*Ubuntu\s{2,}' })
    if ($lines.Count -ne 1 -or $lines[0] -notmatch '\s+([12])\s*$') {
        return New-DotfilesDiagnosticResult Unknown 'Ubuntu WSL version could not be interpreted.'
    }
    if ($Matches[1] -eq '2') { return New-DotfilesDiagnosticResult Passed 'Registered Ubuntu uses WSL 2.' }
    New-DotfilesDiagnosticResult Drift 'Registered Ubuntu still uses WSL 1.'
}

function Get-DotfilesHomeDiagnostic {
    param([string]$UserProfile, [string]$AliasName)
    if ([string]::IsNullOrWhiteSpace($UserProfile)) { return New-DotfilesDiagnosticResult Unknown 'User profile location is unavailable.' }
    if (@($UserProfile.ToCharArray() | Where-Object { [int]$_ -gt 127 }).Count -eq 0) {
        return New-DotfilesDiagnosticResult Skipped 'Profile path is already ASCII-only; setup does not manage a HOME alias.'
    }
    if (-not $PSBoundParameters.ContainsKey('AliasName')) {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        $AliasName = Resolve-DotfilesUserHomeAliasName -WindowsIdentityName $identity -UserName $env:USERNAME
    }
    $currentHome = Get-DotfilesDiagnosticEnvironmentValue -Name HOME -Scope User
    $state = Get-DotfilesUserHomeAliasPreflight -UserProfile $UserProfile -AliasName $AliasName -CurrentHome $currentHome
    switch ($state.Action) {
        'Skip' { return New-DotfilesDiagnosticResult Passed 'Home alias junction and persistent HOME match the setup contract.' }
        'Elevate' { return New-DotfilesDiagnosticResult Drift 'Home alias junction is missing.' }
        'RunNonElevated' { return New-DotfilesDiagnosticResult Drift 'Home alias exists but persistent HOME differs.' }
        default { return New-DotfilesDiagnosticResult Unknown 'Home alias could not be certified; inspect conflicts or access permissions.' }
    }
}
