# dotfiles-windows <release-version> — Acceptance Evidence Pack

> Copy this template outside the repository before filling it. Replace `<release-version>`,
> `<release-branch>`, `<full-release-commit-sha>`, and `<current-production-tag>` with the exact
> candidate values. Execute it alongside `docs/RELEASE_TESTING.md`. Keep raw transcripts and
> screenshots beside the copied file. Before sharing, redact usernames, email addresses, UPNs,
> repository endpoints, tokens, and machine-specific secrets. Do not edit tracked files in the
> tested clone.

## 1. Candidate identity

- Release branch: `<release-branch>`
- Expected commit: `<full-release-commit-sha>`
- Tester:
- Test date/time (Europe/Lisbon):
- Windows edition:
- Windows build (`Get-ComputerInfo | Select-Object WindowsProductName, WindowsVersion, OsBuildNumber`):
- Machine/VM type:
- Entra ID joined: yes / no
- Real profile contains non-ASCII characters: yes / no
- Hypervisor:
- Snapshot before clean install:
- Snapshot before migration test:

## 2. Evidence directory

Create a directory outside the repository:

```powershell
$EvidenceRoot = Join-Path $HOME 'Desktop\dotfiles-windows-<release-version>-evidence'
New-Item -ItemType Directory -Path $EvidenceRoot -Force | Out-Null
$ExpectedCommit = '<full-release-commit-sha>'
```

Record baseline system metadata:

```powershell
Get-Date -Format o | Set-Content "$EvidenceRoot\00-start-time.txt"
Get-ComputerInfo |
    Select-Object WindowsProductName, WindowsVersion, OsBuildNumber, CsManufacturer, CsModel |
    Format-List | Out-File "$EvidenceRoot\00-system.txt"
winget --version | Out-File "$EvidenceRoot\00-winget-version.txt"
```

## 3. Interaction 1 — clean Git-free install

Snapshot restored / baseline ID:

Preconditions checked:

- [ ] Windows 11 Pro or Enterprise
- [ ] Windows PowerShell 5.1 used
- [ ] selected Windows features disabled and capabilities absent
- [ ] persistent clone and local configuration absent
- [ ] Git and PowerShell 7 absent where practical
- [ ] Windows Package Manager available

Run in Windows PowerShell 5.1:

```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
$BootstrapScript = Join-Path $env:TEMP "dotfiles-windows-bootstrap-$([guid]::NewGuid().ToString('N')).ps1"
try {
    Invoke-WebRequest `
        -UseBasicParsing `
        -Uri 'https://raw.githubusercontent.com/abrioso/dotfiles-windows/<release-branch>/setup-scripts/install.ps1' `
        -OutFile $BootstrapScript
    & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
        -NoLogo `
        -NoProfile `
        -ExecutionPolicy Bypass `
        -File $BootstrapScript `
        -Account abrioso `
        -Repo dotfiles-windows `
        -Branch <release-branch> `
        -NonInteractive
    $InstallExitCode = $LASTEXITCODE
    $InstallExitCode | Set-Content "$EvidenceRoot\01-clean-install-exit-code.txt"
} finally {
    Remove-Item -LiteralPath $BootstrapScript -Force -ErrorAction SilentlyContinue
}
```

Record:

- Exit code (expected `3010` when reboot is required):
- Main transcript path:
- Elevated feature/capability transcript path:
- UAC prompts observed:
- Persistent clone path:
- Persistent clone HEAD:

From the persistent clone:

```powershell
git rev-parse HEAD | Tee-Object "$EvidenceRoot\01-clone-head.txt"
git status --short --branch | Tee-Object "$EvidenceRoot\01-git-status.txt"
if ((git rev-parse HEAD) -ne $ExpectedCommit) { throw 'Unexpected release candidate commit.' }
```

Checks:

- [ ] archive root resolved correctly
- [ ] local JSON created from release templates
- [ ] `Microsoft.PowerShell` and `Git.Git` installed at user scope
- [ ] PowerShell used MSIX rather than MSI/WiX
- [ ] PATH refresh exposed `pwsh` and `git`
- [ ] setup relaunched from Windows PowerShell 5.1 into PowerShell 7
- [ ] clone is at the expected commit
- [ ] local gitignored JSON reached the clone
- [ ] selected Windows features requested elevation once
- [ ] `3010` propagated through all wrappers
- [ ] no downstream WSL/Docker/settings modules ran before reboot
- [ ] all reported transcript files exist
- [ ] tracked working tree remained clean

Notes / deviations:

## 4. Interaction 2 — post-reboot continuation

Reboot completed at:

Set and verify the exact package order in the persistent clone:

```powershell
$bootstrapPath = '.\dotfiles-configurations\dotfiles-bootstrap-variables.json'
$bootstrap = Get-Content -LiteralPath $bootstrapPath -Raw | ConvertFrom-Json
$expectedPackageGroups = @(
    'base', 'browsers', 'development', 'wsl', 'docker', 'multimedia',
    'PowerBI', 'productivity', 'pwsh', 'poweruser', 'tailscale', 'google-drive'
)
$bootstrap.INSTALL_PACKAGES = $expectedPackageGroups
$bootstrap | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $bootstrapPath -Encoding utf8
$actualPackageGroups = @((Get-Content -LiteralPath $bootstrapPath -Raw | ConvertFrom-Json).INSTALL_PACKAGES)
if (($actualPackageGroups -join "`n") -cne ($expectedPackageGroups -join "`n")) {
    throw "Acceptance package groups are missing or out of order: $($actualPackageGroups -join ', ')."
}
```

Run:

```powershell
git status --short --branch | Tee-Object "$EvidenceRoot\02-pre-setup-status.txt"
git rev-parse HEAD | Tee-Object "$EvidenceRoot\02-pre-setup-head.txt"
.\setup-scripts\setup.ps1
$SetupExitCode = $LASTEXITCODE
$SetupExitCode | Set-Content "$EvidenceRoot\02-setup-exit-code.txt"
```

If capabilities return `3010`, record it, reboot, and rerun Interaction 2 before evaluating Winget.

Record:

- Setup exit code:
- Main transcript path:
- Elevated transcript path:
- Capability reboot required: yes / no
- Number and purpose of UAC prompts:

Checks:

- [ ] already-enabled features skipped without feature UAC
- [ ] capabilities installed in declared order
- [ ] capability `3010` stopped execution before Winget
- [ ] failures stopped the remaining plan and propagated non-zero status
- [ ] no `No applicable installer`, `0x8A150010`, or hash mismatch
- [ ] PowerShell and Windows Terminal remained user-scoped MSIX
- [ ] Tailscale installed machine-wide
- [ ] Google Drive installed machine-wide
- [ ] WSL package preceded Ubuntu and WSL completed before Docker

Capture state:

```powershell
winget list --id Tailscale.Tailscale --exact | Out-File "$EvidenceRoot\02-tailscale.txt"
winget list --id Google.GoogleDrive --exact | Out-File "$EvidenceRoot\02-google-drive.txt"
wsl --version | Out-File "$EvidenceRoot\02-wsl-version.txt"
wsl --status | Out-File "$EvidenceRoot\02-wsl-status.txt"
wsl --list --verbose | Out-File "$EvidenceRoot\02-wsl-list.txt"
docker run --rm hello-world | Out-File "$EvidenceRoot\02-docker-hello-world.txt"
git status --short | Out-File "$EvidenceRoot\02-final-git-status.txt"
```

User/settings checks:

- [ ] `C:\Users\<upn-prefix>` is a junction to the real accented profile
- [ ] new terminal exposes the alias through `$HOME` and user environment
- [ ] `$env:USERPROFILE` remains the real profile path
- [ ] Nerd Font is installed once and renders correctly
- [ ] Windows Terminal live settings are in package `LocalState`, not a repo symlink
- [ ] dynamic profiles do not dirty Git
- [ ] PowerShell profiles are local copies with marker stubs
- [ ] PowerShell 7 and VS Code load expected profiles
- [ ] Oh My Posh and Git configuration work
- [ ] setup succeeds and Git remains clean

Notes / deviations:

## 5. Interaction 3 — idempotency

```powershell
.\setup-scripts\setup.ps1
$IdempotencyExitCode = $LASTEXITCODE
$IdempotencyExitCode | Set-Content "$EvidenceRoot\03-idempotency-exit-code.txt"
git status --short | Set-Content "$EvidenceRoot\03-git-status.txt"
```

- Exit code:
- Transcript path:
- UAC prompts observed:

Checks:

- [ ] no reboot requested
- [ ] no Windows feature elevation
- [ ] installed packages skipped, including Tailscale and Google Drive
- [ ] no machine installer UAC on rerun
- [ ] HOME junction/environment unchanged
- [ ] no duplicate fonts, profiles, links, or settings
- [ ] local Terminal/profile edits preserved
- [ ] Git remains clean

Notes / deviations:

## 6. Existing-install migration

Start from a snapshot installed from current production `main` / tag `<current-production-tag>`.

- Baseline snapshot ID:
- Baseline commit/tag:
- Migration start time:

Follow `docs/RELEASE_TESTING.md`, section **Existing-install migration**.

- [ ] shared catalogs updated through `setup-scripts\update.ps1`
- [ ] backups stored outside the checkout
- [ ] identity, endpoint, environment, and Git variables preserved
- [ ] invalid templates fail before replacement
- [ ] old PowerShell profile links migrate without losing user-authored files
- [ ] Windows Terminal layout migrates with recoverable backup
- [ ] first migrated run succeeds
- [ ] second migrated run is idempotent
- [ ] Git remains clean

Backup directory:

First-run transcript / exit code:

Second-run transcript / exit code:

Notes / deviations:

## 7. Repeated Git-free invocation

From the release candidate installation, choose two non-secret local JSON files:

- Existing personalised JSON to preserve:
- Different JSON temporarily moved outside the repository:
- Backup/snapshot ID:

Record the existing file hash and move the different file:

```powershell
$PreservedFile = '<absolute path to existing local JSON>'
$MissingFile = '<absolute path to a different local JSON>'
$MissingBackup = Join-Path $EvidenceRoot ('backup-' + (Split-Path $MissingFile -Leaf))
$BeforeHash = (Get-FileHash -LiteralPath $PreservedFile -Algorithm SHA256).Hash
$BeforeHash | Set-Content "$EvidenceRoot\07-preserved-before.sha256"
Move-Item -LiteralPath $MissingFile -Destination $MissingBackup
```

Repeat the same Git-free command from Interaction 1, then verify:

```powershell
$AfterHash = (Get-FileHash -LiteralPath $PreservedFile -Algorithm SHA256).Hash
$AfterHash | Set-Content "$EvidenceRoot\07-preserved-after.sha256"
if ($AfterHash -cne $BeforeHash) { throw 'Existing local configuration was replaced.' }
if (-not (Test-Path -LiteralPath $MissingFile -PathType Leaf)) { throw 'Missing local configuration was not populated.' }
```

- [ ] preserved hash unchanged
- [ ] missing JSON recreated from the release template
- [ ] transcript contains `Skipped existing local configuration`
- [ ] transcript contains `Copied local configuration` for the missing file
- [ ] snapshot restored after this scenario

Transcript path:

Exit code:

Notes / deviations:

## 8. Final verdict

- [ ] All required scenarios passed on expected commit `<full-release-commit-sha>`
- [ ] No tracked file changed
- [ ] All transcript and evidence paths exist
- [ ] Evidence reviewed for PII/secrets before sharing

Result: PASS / FAIL / BLOCKED

Blocking findings:

Known limitations accepted for this release:

Tester sign-off:

Date/time:
