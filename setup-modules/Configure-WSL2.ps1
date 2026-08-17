<#
.SYNOPSIS
    Enforces WSL 2 for the default and configured Ubuntu distribution.

.DESCRIPTION
    Sets WSL 2 as the default for future distribution registrations. If Ubuntu
    is already registered, converts it to WSL 2 idempotently. This module runs
    after Winget installs the WSL runtime and distribution package.
#>
param (
    [string]$WslCommand = 'wsl.exe',
    [string]$DistributionName = 'Ubuntu'
)

try {
    if (-not (Get-Command $WslCommand -ErrorAction SilentlyContinue)) {
        throw "WSL command '$WslCommand' is unavailable after package installation."
    }

    Write-Host 'Setting WSL 2 as the default for new distributions...'
    & $WslCommand --set-default-version 2 | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to set WSL 2 as the default. WSL exited with code $LASTEXITCODE."
    }

    $registeredDistributions = @(& $WslCommand --list --quiet)
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to list registered WSL distributions. WSL exited with code $LASTEXITCODE."
    }

    $normalizedNames = @($registeredDistributions | ForEach-Object {
        ([string]$_ -replace "`0", '').Trim()
    } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

    if ($normalizedNames -contains $DistributionName) {
        $distributionList = @(& $WslCommand --list --verbose)
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to inspect registered WSL distributions. WSL exited with code $LASTEXITCODE."
        }

        $normalizedLines = @($distributionList | ForEach-Object {
            ([string]$_ -replace "`0", '').Trim()
        } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        $distributionPattern = '^\*?\s*' + [regex]::Escape($DistributionName) + '\s{2,}'
        $distributionLine = $normalizedLines | Where-Object { $_ -match $distributionPattern } | Select-Object -First 1

        if (-not $distributionLine -or $distributionLine -notmatch '\s+([12])\s*$') {
            throw "Could not determine the WSL version for registered distribution '$DistributionName'."
        }

        $distributionVersion = [int]$Matches[1]
        if ($distributionVersion -eq 1) {
            Write-Host "Converting WSL distribution '$DistributionName' from WSL 1 to WSL 2..."
            & $WslCommand --set-version $DistributionName 2 | Out-Host
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to configure '$DistributionName' for WSL 2. WSL exited with code $LASTEXITCODE."
            }
        } else {
            Write-Host "WSL distribution '$DistributionName' already uses WSL 2."
        }
    } else {
        Write-Host "Distribution '$DistributionName' is not registered yet. Its first launch will use the WSL 2 default."
    }
}
catch {
    Write-Error "An error occurred while enforcing WSL 2 state: $_"
    exit 1
}

Write-Host 'WSL 2 configuration complete.'
