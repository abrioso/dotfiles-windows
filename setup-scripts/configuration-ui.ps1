function Test-DotfilesToggleConsole {
    try {
        return $Host.Name -eq 'ConsoleHost' -and -not [Console]::IsInputRedirected -and
            -not [Console]::IsOutputRedirected -and [Console]::WindowWidth -ge 30 -and
            [Console]::WindowHeight -ge 8
    } catch { return $false }
}

function Read-DotfilesSelectionKey {
    [Console]::ReadKey($true).Key.ToString()
}

function Show-DotfilesSelection {
    param([string[]]$Choices, [bool[]]$Selected, [int]$Index, [int]$Top, [int]$Rows)
    $width = [Math]::Max(1, [Console]::WindowWidth - 1)
    $first = [Math]::Max(0, [Math]::Min($Index - $Rows + 1, $Choices.Count - $Rows))
    [Console]::SetCursorPosition(0, $Top)
    for ($row = 0; $row -lt $Rows; $row++) {
        $item = $first + $row
        $line = ''
        if ($item -lt $Choices.Count) {
            $pointer = if ($item -eq $Index) { '>' } else { ' ' }
            $mark = if ($Selected[$item]) { 'x' } else { ' ' }
            $line = '{0} [{1}] {2}' -f $pointer, $mark, $Choices[$item]
        }
        if ($line.Length -gt $width) { $line = $line.Substring(0, $width) }
        [Console]::WriteLine($line.PadRight($width))
    }
}

function Read-DotfilesMultiSelection {
    [CmdletBinding()]
    param(
        [string]$Label,
        [AllowEmptyCollection()][string[]]$Choices,
        [AllowNull()][object[]]$CurrentValues,
        [scriptblock]$ReadKey = { Read-DotfilesSelectionKey },
        [scriptblock]$Render,
        [switch]$TextMode
    )
    if ($Choices.Count -eq 0) { return }
    $selected = [bool[]]@($Choices | ForEach-Object { $CurrentValues -contains $_ })
    if ($TextMode) {
        while ($true) {
            Write-Host $Label
            for ($i = 0; $i -lt $Choices.Count; $i++) {
                $mark = if ($selected[$i]) { 'x' } else { ' ' }
                Write-Host ('  {0}) [{1}] {2}' -f ($i + 1), $mark, $Choices[$i])
            }
            $answer = Read-Host 'Choose comma-separated numbers, all, none, Enter to keep, or cancel'
            if ($answer -eq 'cancel') { throw [OperationCanceledException]::new('Configuration cancelled. Selections were not saved.') }
            if ([string]::IsNullOrWhiteSpace($answer)) { break }
            if ($answer.Trim() -eq 'all') { $selected = [bool[]]@($Choices | ForEach-Object { $true }); break }
            if ($answer.Trim() -eq 'none') { $selected = [bool[]]@($Choices | ForEach-Object { $false }); break }
            $next = [bool[]]::new($Choices.Count)
            $valid = $true
            foreach ($part in ($answer -split ',')) {
                $number = 0
                if (-not [int]::TryParse($part.Trim(), [ref]$number) -or $number -lt 1 -or $number -gt $Choices.Count) {
                    $valid = $false
                    break
                }
                $next[$number - 1] = $true
            }
            if ($valid) { $selected = $next; break }
            Write-Warning 'Invalid selection. Previous choices are unchanged; please try again.'
        }
    } else {
        $index = 0
        $top = 0
        $rows = [Math]::Min(10, $Choices.Count)
        if (-not $Render) {
            Write-Host $Label
            Write-Host 'Up/Down: move | Space: toggle | A: all | N: none | Enter: confirm | Esc: cancel'
            $rows = [Math]::Min($rows, [Math]::Max(1, [Console]::WindowHeight - 5))
            for ($i = 0; $i -lt $rows; $i++) { [Console]::WriteLine() }
            $top = [Math]::Max(0, [Console]::CursorTop - $rows)
            $Render = { param($Items, $Flags, $Focus, $Start, $Count) Show-DotfilesSelection $Items $Flags $Focus $Start $Count }
        }
        try {
            while ($true) {
                & $Render $Choices $selected $index $top $rows | Out-Null
                $key = & $ReadKey
                if ($key -eq 'Enter') { break }
                switch ($key) {
                    'UpArrow' { $index = ($index + $Choices.Count - 1) % $Choices.Count }
                    'DownArrow' { $index = ($index + 1) % $Choices.Count }
                    'Home' { $index = 0 }
                    'End' { $index = $Choices.Count - 1 }
                    'Spacebar' { $selected[$index] = -not $selected[$index] }
                    'A' { for ($i = 0; $i -lt $selected.Count; $i++) { $selected[$i] = $true } }
                    'N' { for ($i = 0; $i -lt $selected.Count; $i++) { $selected[$i] = $false } }
                    'Escape' { throw [OperationCanceledException]::new('Configuration cancelled. Selections were not saved.') }
                }
            }
        } finally {
            # Leave subsequent prompts below the selector, including after cancellation.
            if ($top -gt 0) { [Console]::SetCursorPosition(0, $top + $rows) }
        }
    }
    # Existing selections keep their order; newly enabled choices follow catalog order.
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($choice in (@($CurrentValues) + @($Choices))) {
        for ($i = 0; $i -lt $Choices.Count; $i++) {
            if ($choice -eq $Choices[$i] -and $selected[$i] -and $seen.Add($Choices[$i])) { $Choices[$i] }
        }
    }
}

function Save-DotfilesConfiguration {
    [CmdletBinding()]
    param([string]$ConfigDirectory, [string]$ModuleDirectory, $Bootstrap, $GitConfig)
    # .NET file replacement resolves paths against the process directory, not Get-Location.
    $ConfigDirectory = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ConfigDirectory)
    # Reuse the updater's atomic replacement, backup and rollback implementation.
    . "$PSScriptRoot/update-functions.ps1"
    Set-StrictMode -Off
    $stage = Join-Path ([IO.Path]::GetTempPath()) ('dotfiles-config-' + [guid]::NewGuid().ToString('N'))
    $backupBase = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { [IO.Path]::GetTempPath() }
    $backupDirectory = Join-Path $backupBase ('dotfiles-windows/config-backups/' + [guid]::NewGuid().ToString('N'))
    $updated = [Collections.Generic.List[object]]::new()
    try {
        $null = New-Item -ItemType Directory -Path $stage -ErrorAction Stop
        foreach ($name in Get-DotfilesConfigFile) {
            Copy-Item -LiteralPath (Join-Path $ConfigDirectory $name) -Destination $stage -ErrorAction Stop
        }
        $Bootstrap | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $stage 'dotfiles-bootstrap-variables.json') -Encoding UTF8 -ErrorAction Stop
        $GitConfig | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $stage 'git-variables.json') -Encoding UTF8 -ErrorAction Stop
        Assert-DotfilesSetupConfiguration -DotfilesVariables $Bootstrap -ConfigDirectory $stage -ModuleDirectory $ModuleDirectory
        foreach ($name in @('dotfiles-bootstrap-variables.json', 'git-variables.json')) {
            $updated.Add((Update-DotfilesConfigurationTemplate -TemplatePath (Join-Path $stage $name) `
                -TargetPath (Join-Path $ConfigDirectory $name) -BackupDirectory $backupDirectory))
        }
    } catch {
        $saveError = $_
        for ($i = $updated.Count - 1; $i -ge 0; $i--) {
            try { Restore-DotfilesConfigurationTemplate -UpdateResult $updated[$i] }
            catch { Write-Warning "Rollback failed. Recover configuration from '$backupDirectory'." }
        }
        throw $saveError
    } finally {
        if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
