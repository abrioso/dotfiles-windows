# Release testing

This checklist is the acceptance gate for promoting `develop` through a
`release/vYYYY.MM.N` branch into `main`. Record the tested commit, Windows build, machine type,
and evidence for every required scenario. Copy
[RELEASE_EVIDENCE_TEMPLATE.md](RELEASE_EVIDENCE_TEMPLATE.md) outside the repository before filling
it; completed evidence and raw artifacts must not modify the release candidate under test.

## Test topology

Use a disposable Windows 11 Pro or Enterprise machine or VM with snapshots. An Entra ID joined
machine whose real profile path contains non-ASCII characters is required for the `HOME` alias
scenario. Use the default package, feature, capability, and setting selections unless a scenario
says otherwise. Azure, Power BI, Tailscale, Delinea, Yubico and Google Drive remain opt-in; select
all six explicitly for the package acceptance scenario without adding them to the tracked defaults.

The three main interactions do **not** all use the Git-free entry point:

1. **Clean install:** start with the Git-free bootstrap from Windows PowerShell 5.1.
2. **Post-reboot continuation:** run `setup.ps1` from the persistent workspace clone.
3. **Idempotency:** run `setup.ps1` from the same persistent clone again.

The Git-free archive is a bootstrap transport, not the persistent checkout. Re-running it creates
fresh local JSON from the archive templates, copies only files missing from the persistent clone,
and preserves existing machine-local JSON. After synchronization, setup reloads the persistent
bootstrap configuration before validating dependencies and building the module plan. Saved choices
therefore control both orchestration and modules. `-BootstrapBranch` selects the initial clone branch
or verifies an existing branch without switching it or replacing saved configuration. Update code
explicitly using `update.ps1` before apply when needed. Initial repository location and
endpoint selection still come from the bootstrap transport. For post-reboot continuation, execute
`setup.ps1` from the persistent clone. Test repeated Git-free invocation separately as described below.

## Evidence to capture

For profile acceptance, launch both PowerShell 7 console and the VS Code PowerShell
extension after apply. Confirm both load the same machine-local `common.ps1`, UTF-8
output and available optional tools. Check that missing Terminal-Icons or Oh My Posh
does not prevent startup, personal Documents profiles remain unchanged, and support
files have no obsolete unmodified managed Documents stubs. Edited stubs, links and personal
files must be preserved for manual review. Rerun apply and verify unchanged file timestamps.

For each interaction, retain:

- the exact Git commit under test;
- the setup transcript and any elevated Windows feature or capability transcript;
- the process exit code;
- screenshots or command output for UAC, WSL, Docker, package and filesystem checks;
- `git status --short` from the persistent clone.

Never publish transcripts or configuration backups before checking them for usernames, email
addresses, repository endpoints, tokens, or other machine-specific values.

## Step-by-step execution

Run the command blocks in order, completing the corresponding acceptance checks below each
interaction. These commands do not replace the negative, migration and recovery scenarios.
Use a normal, non-elevated console; accept UAC only for the selected operations that require it.
Export evidence outside the VM before restoring snapshots. Record unavailable scenarios as
unexecuted, rather than passed.

### Step 1: identify the candidate and prepare evidence

Start in Windows PowerShell 5.1 on the clean VM. Use `develop` for preliminary testing and the
exact `release/vYYYY.MM.N` branch for final acceptance. Obtain its full commit from the candidate
review; do not reuse an old example SHA. Keep that branch unchanged throughout the run.
An optional archive SHA-256 must come from a trusted source; calculating a hash of the same
unverified download does not independently authenticate it.

```powershell
$ErrorActionPreference = 'Stop'
$Branch = Read-Host 'Candidate branch (develop or release/vYYYY.MM.N)'
$ExpectedCommit = Read-Host 'Expected full candidate commit (40 hexadecimal characters)'
if ([string]::IsNullOrWhiteSpace($Branch) -or $ExpectedCommit -notmatch '^[0-9a-fA-F]{40}$') {
    throw 'A candidate branch and full commit are required.'
}
$ArchiveSha256 = Read-Host 'Trusted archive SHA-256 (optional; press Enter for compatibility mode)'
if ($ArchiveSha256 -and $ArchiveSha256 -notmatch '^[0-9a-fA-F]{64}$') {
    throw 'Archive SHA-256 must have 64 hexadecimal characters.'
}
$EvidenceRoot = Join-Path $env:LOCALAPPDATA 'dotfiles-acceptance'
$ClonePath = Join-Path $env:USERPROFILE 'workspace\dotfiles-windows'
$BootstrapScript = Join-Path $EvidenceRoot 'bootstrap.ps1'
$StatePath = Join-Path $EvidenceRoot 'candidate.json'
if (Test-Path -LiteralPath $StatePath) {
    throw 'Evidence already exists. Resume step 3 or choose a separate evidence directory.'
}
New-Item -ItemType Directory -Path $EvidenceRoot -Force | Out-Null
[pscustomobject]@{
    Branch = $Branch
    ExpectedCommit = $ExpectedCommit
    ArchiveSha256 = $ArchiveSha256
    ClonePath = $ClonePath
} | ConvertTo-Json | Set-Content -LiteralPath $StatePath -Encoding utf8
Get-Date -Format o | Set-Content "$EvidenceRoot\00-start-time.txt"
Get-ComputerInfo |
    Select-Object WindowsProductName, WindowsVersion, OsBuildNumber, CsManufacturer, CsModel |
    Format-List | Out-File "$EvidenceRoot\00-system.txt"
$PSVersionTable | Out-File "$EvidenceRoot\00-powershell.txt"
winget --version | Out-File "$EvidenceRoot\00-winget-version.txt"
if ($LASTEXITCODE -ne 0) { throw 'Windows Package Manager is unavailable.' }
```

The clone path above assumes the tracked `workspace` default. Adjust it in the saved state if
testing a deliberately different workspace. On a separate migration VM, prepare the same candidate
identity/evidence variables, then follow **Existing-install migration**, not the clean-install step.

## Interaction 1: clean Git-free install

### Preconditions

- Start from a snapshot with the selected Windows optional features disabled and capabilities absent.
- Remove any previous persistent dotfiles clone, local dotfiles configuration, `HOME` alias,
  Windows Terminal baseline, and repo-managed PowerShell profiles.
- Ensure Windows Package Manager is available. Git and PowerShell 7 should be absent when testing
  prerequisite installation.
- Start from the in-box Windows PowerShell 5.1 host, not `pwsh`.

### Step 2: bootstrap and record the exit code

Take the clean-install snapshot first. Run the installer in a child Windows PowerShell 5.1
process so its `exit` does not close the evidence console. The installer script is fetched from
the expected commit. With a trusted archive hash, the archive and initial clone are pinned to
that commit too. Without it, the installer warns about compatibility mode and downloads the
branch archive; a moving branch invalidates the run and must be investigated at step 3.

```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
if (Test-Path -LiteralPath $ClonePath) { throw 'Use a clean snapshot: the clone already exists.' }
Invoke-WebRequest -UseBasicParsing `
    -Uri "https://raw.githubusercontent.com/abrioso/dotfiles-windows/$ExpectedCommit/setup-scripts/install.ps1" `
    -OutFile $BootstrapScript
$InstallArguments = @('-Account', 'abrioso', '-Repo', 'dotfiles-windows', '-Branch', $Branch, '-NonInteractive')
if ($ArchiveSha256) {
    $InstallArguments += @('-Commit', $ExpectedCommit, '-ArchiveSha256', $ArchiveSha256)
}
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
    -NoProfile -File $BootstrapScript @InstallArguments
$InstallExitCode = $LASTEXITCODE
$InstallExitCode | Set-Content "$EvidenceRoot\01-install-exit-code.txt"
if ($InstallExitCode -notin @(0, 3010)) { throw "Bootstrap failed: $InstallExitCode. Retain its logs." }
if ($InstallExitCode -eq 3010) { Write-Warning 'Reboot required. Complete the checks below, then restart before step 3.' }
```

### Acceptance checks

- [ ] The archive downloads and its extracted root is resolved correctly.
- [ ] Local JSON configuration is created from the selected branch templates.
- [ ] With shared defaults, missing `Git.Git` installs with machine scope, requesting elevation
      when required; missing `Microsoft.PowerShell` installs with user scope using its MSIX package
      rather than the MSI/WiX installer.
- [ ] In a separate custom-configuration scenario with Git absent, a selected `Git.Git` declaration
      with user scope is passed to WinGet during bootstrap and agrees with the subsequent package
      module check. The bootstrap does not force the machine default over the selected declaration.
- [ ] PATH refresh makes both `pwsh` and `git` available to the running bootstrap.
- [ ] Windows PowerShell 5.1 relaunches setup in PowerShell 7 before repository Git operations.
- [ ] The persistent clone is created under the configured workspace.
- [ ] The clone checks out the requested `develop` or `release/vYYYY.MM.N` branch and its HEAD is
      the expected commit.
- [ ] Local gitignored JSON from the bootstrap copy reaches the persistent clone.
- [ ] The generated `INSTALL_PACKAGES` value exactly matches the tracked defaults: `base`,
      `browsers`, `dev`, `wsl`, `docker`, `multimedia`, `productivity`, `pwsh`, `poweruser`.
- [ ] None of `azure`, `powerbi`, `tailscale`, `delinea`, `yubico` or `google-drive` is selected
      before the package acceptance override.
- [ ] The Windows feature module runs under Windows PowerShell 5.1 and requests elevation once.
- [ ] Enabling the selected features returns exit code `3010` when a reboot is required.
- [ ] The Git-free wrapper returns the same `3010` exit code.
- [ ] Package modules after the Windows feature boundary do not run before reboot. Bootstrap
      prerequisites are expected; WSL, Ubuntu, Docker and settings are not.
- [ ] Both the main and elevated module transcript paths are reported and the files exist.
- [ ] No tracked file in the persistent clone is modified. Setup created the clone directly on the
      requested branch without a subsequent fetch/pull.

If the result is `3010`, stop here after saving transcript paths and restart Windows:

```powershell
Restart-Computer
```

A zero exit code does not demonstrate the reboot boundary: record whether the clean-install
preconditions were actually satisfied. Do not mark an untested reboot scenario as passed.

## Interaction 2: post-reboot continuation

### Step 3: restore session state and verify the clone

Open PowerShell 7 after each reboot. Repeat this block after changing consoles too; variables
do not survive a reboot. If you chose another evidence directory in step 1, use that same path.

```powershell
$ErrorActionPreference = 'Stop'
$EvidenceRoot = Join-Path $env:LOCALAPPDATA 'dotfiles-acceptance'
$Candidate = Get-Content -LiteralPath (Join-Path $EvidenceRoot 'candidate.json') -Raw | ConvertFrom-Json
$Branch = $Candidate.Branch
$ExpectedCommit = $Candidate.ExpectedCommit
$ArchiveSha256 = $Candidate.ArchiveSha256
$ClonePath = $Candidate.ClonePath
$BootstrapScript = Join-Path $EvidenceRoot 'bootstrap.ps1'
Set-Location -LiteralPath $ClonePath
$ActualCommit = git rev-parse HEAD
if ($LASTEXITCODE -ne 0 -or $ActualCommit -ne $ExpectedCommit) { throw 'Unexpected candidate commit.' }
$ActualBranch = git branch --show-current
if ($LASTEXITCODE -ne 0 -or $ActualBranch -ne $Branch) { throw 'Unexpected candidate branch.' }
git status --short --branch | Out-File "$EvidenceRoot\02-clone-status.txt"
$ActualCommit | Set-Content "$EvidenceRoot\02-clone-head.txt"
if (-not (Test-Path -LiteralPath "$EvidenceRoot\acceptance.md")) {
    Copy-Item -LiteralPath '.\docs\RELEASE_EVIDENCE_TEMPLATE.md' -Destination "$EvidenceRoot\acceptance.md"
}
```

Only before the first package-selection override, verify the original defaults:

```powershell
$BootstrapPath = '.\dotfiles-configurations\dotfiles-bootstrap-variables.json'
$Bootstrap = Get-Content -LiteralPath $BootstrapPath -Raw | ConvertFrom-Json
$ExpectedDefaults = @('base', 'browsers', 'dev', 'wsl', 'docker', 'multimedia', 'productivity', 'pwsh', 'poweruser')
if (($Bootstrap.INSTALL_PACKAGES -join "`n") -cne ($ExpectedDefaults -join "`n")) {
    throw 'Unexpected initial default package groups.'
}
```

### Step 4: select acceptance packages and preview

Before the first post-reboot setup run, set the exact
ordered package selection for this acceptance scenario: the tracked defaults plus all six opt-in
groups. This deliberately edits only the local, gitignored bootstrap configuration:

```powershell
$bootstrapPath = '.\dotfiles-configurations\dotfiles-bootstrap-variables.json'
$bootstrap = Get-Content -LiteralPath $bootstrapPath -Raw | ConvertFrom-Json
$expectedPackageGroups = @(
    'base',
    'browsers',
    'dev',
    'azure',
    'wsl',
    'docker',
    'multimedia',
    'powerbi',
    'productivity',
    'pwsh',
    'poweruser',
    'tailscale',
    'delinea',
    'yubico',
    'google-drive'
)
$bootstrap.INSTALL_PACKAGES = $expectedPackageGroups
$bootstrap | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $bootstrapPath -Encoding utf8

$actualPackageGroups = @(
    (Get-Content -LiteralPath $bootstrapPath -Raw | ConvertFrom-Json).INSTALL_PACKAGES
)
if (($actualPackageGroups -join "`n") -cne ($expectedPackageGroups -join "`n")) {
    throw "Acceptance package groups are missing or out of order: $($actualPackageGroups -join ', ')."
}
```

Preview the selected plan without applying it:

```powershell
& pwsh -NoProfile -File .\setup-scripts\setup.ps1 -Plan -PlanFormat Json |
    Set-Content "$EvidenceRoot\02-plan.json" -Encoding utf8
if ($LASTEXITCODE -ne 0) { throw 'Setup plan failed.' }
Get-Content "$EvidenceRoot\02-plan.json"
git status --short
```

Confirm the plan did not install anything, request UAC or create setup logs. Git must stay clean.

### Step 5: apply from the persistent clone

```powershell
& pwsh -NoProfile -File .\setup-scripts\setup.ps1 -NonInteractive
$SetupExitCode = $LASTEXITCODE
$Attempt = Get-Date -Format 'yyyyMMdd-HHmmssfff'
$SetupExitCode | Set-Content "$EvidenceRoot\02-setup-$Attempt-exit-code.txt"
if ($SetupExitCode -notin @(0, 3010)) { throw "Setup failed: $SetupExitCode. Retain its logs." }
if ($SetupExitCode -eq 3010) { throw 'Reboot required: restart Windows, restore step 3 session state, then repeat step 5.' }
```

On `3010`, stop before the downstream checks, save the transcript paths and reboot with
`Restart-Computer`. Resume from the clone, never from the Git-free bootstrap. Do not repeat the
initial-default check after packages have been deliberately overridden.

### Step 6: diagnose installed state

```powershell
& pwsh -NoProfile -File .\setup-scripts\verify.ps1 -Format Json -CheckPackages |
    Set-Content "$EvidenceRoot\03-diagnostic.json" -Encoding utf8
$DiagnosticExitCode = $LASTEXITCODE
$DiagnosticExitCode | Set-Content "$EvidenceRoot\03-diagnostic-exit-code.txt"
$Report = Get-Content "$EvidenceRoot\03-diagnostic.json" -Raw | ConvertFrom-Json
$Report.Counts | Format-List
$Report.Checks | Where-Object Status -In @('Drift', 'Unknown') |
    Format-Table Category, Name, Status, Message -Wrap
```

Exit `1` means drift was detected; investigate and correct it before acceptance. Exit `2` means
inconclusive checks or invalid configuration without confirmed drift. Inspect each `Unknown`;
installed installer type and components without probes can remain inconclusive even after a
successful install. Exit `0` covers implemented passed/skipped checks, not the interactive checks
below. Package queries can contact WinGet sources and write native caches/logs.

### Feature and orchestration checks

- [ ] The clone is still on the requested integration or release branch at the expected commit.
- [ ] Already-enabled Windows features pass the non-elevated preflight and do not cause another
      feature UAC prompt.
- [ ] Setup continues beyond the reboot boundary and executes modules in documented order.
- [ ] Selected Windows capabilities install in declared order under Windows PowerShell 5.1.
- [ ] If capability installation returns `3010`, setup stops before Winget; restart Windows and
      repeat this interaction before evaluating downstream modules.
- [ ] A module failure stops the remaining plan and returns a non-zero exit code.

### Winget checks

- [ ] Every selected package either installs or is detected as already installed.
- [ ] Presence checks and post-install checks match each requested scope; installer success
      alone is not reported as verified state. Run `verify.ps1 -CheckPackages` and retain evidence.
- [ ] On a disposable snapshot, preinstall a package only in the other scope: apply must
      report the mismatch without uninstalling, duplicating it or requesting an install UAC.
- [ ] Source/query failures remain inconclusive and do not trigger installs. Requested
      installer types remain `Unknown` in the diagnostic even when presence/scope match.
- [ ] A non-admin machine query returning access denied uses the non-elevated inventory
      fallback for missing/machine-only packages; overlap and fallback errors remain Unknown.
- [ ] No package reports `No applicable installer`, `0x8A150010`, hash mismatch, or an ignored
      non-zero Winget exit code.
- [ ] `Microsoft.PowerShell` and `Microsoft.WindowsTerminal` remain user-scoped MSIX packages.
- [ ] `Yaak.app` installs at user scope.
- [ ] `7zip.7zip` installs at machine scope.
- [ ] Packages declared with machine scope request UAC only when installation is required.
- [ ] `azure` installs `Microsoft.Azd` and `Microsoft.AzureCLI`; `powerbi` installs
      `Microsoft.PowerBI`.
- [ ] `tailscale`, `delinea`, `yubico` and `google-drive` install their declared machine-scoped
      packages and every opt-in package is detected as installed on the idempotency run.
- [ ] `Microsoft.WSL` installs before `Canonical.Ubuntu`, and the WSL group completes before
      Docker Desktop.

### WSL and Docker checks

#### Step 7: check WSL and Docker

Launch Ubuntu once if user creation is still required. Open Docker Desktop and wait until its
engine is ready before running the container check. Retain the output and inspect every exit code.

```powershell
wsl --version
if ($LASTEXITCODE -ne 0) { throw 'WSL version query failed.' }
wsl --status
if ($LASTEXITCODE -ne 0) { throw 'WSL status query failed.' }
wsl --list --verbose
if ($LASTEXITCODE -ne 0) { throw 'WSL distribution query failed.' }
docker run --rm hello-world
if ($LASTEXITCODE -ne 0) { throw 'Docker hello-world failed.' }
```

- [ ] WSL commands complete successfully.
- [ ] Ubuntu is registered as WSL version 2, or its not-yet-registered state is reported clearly
      with WSL 2 set as the default for first launch.
- [ ] Docker Desktop uses the intended backend and `hello-world` succeeds.

### User and terminal settings checks

#### Step 8: check both profile hosts and terminal settings

Open a new PowerShell 7 console and run the following. Repeat it in the PowerShell extension's
Integrated Console in VS Code, not just an ordinary VS Code terminal. Check the prompt, icons and
characters visually; a file hash alone does not demonstrate successful interactive loading.

```powershell
$PROFILE.CurrentUserCurrentHost
[Console]::OutputEncoding.WebName
Get-Module Terminal-Icons
Get-Command oh-my-posh -ErrorAction SilentlyContinue
$LocalProfiles = Join-Path $env:LOCALAPPDATA 'dotfiles\powershell-profiles'
Get-ChildItem -LiteralPath $LocalProfiles -Filter '*.ps1' -File | Select-Object Name, LastWriteTimeUtc
Get-FileHash -LiteralPath (Join-Path $LocalProfiles 'common.ps1')
Write-Host 'UTF-8 check: ação, configuração, André'
```

The deployed `common.ps1` hash must match `powershell-profiles/common.ps1` in the candidate.
On the accented Entra ID profile, inspect the alias in a newly opened console:

```powershell
$HOME
$env:USERPROFILE
[Environment]::GetEnvironmentVariable('HOME', 'User')
Get-Item -LiteralPath $HOME -Force | Select-Object FullName, LinkType, Target
```

After Windows Terminal creates its dynamic profiles, restore the step 3 session variables and run
`git -C $ClonePath status --short`; expect no tracked or untracked repository changes. Record an
unavailable Entra ID/OneDrive/host scenario as unexecuted.

- [ ] On an accented Entra ID profile, `C:\Users\<upn-prefix>` is a junction to the real profile.
- [ ] A newly opened terminal reports the alias through `$HOME` and the user environment variable.
- [ ] `$env:USERPROFILE` remains the real Windows profile path and is never rewritten.
- [ ] CaskaydiaCove Nerd Font is installed for the current user and renders expected terminal icons.
- [ ] Windows Terminal creates its live `settings.json` under package `LocalState` without a
      repository symlink.
- [ ] Opening Windows Terminal and allowing WSL/dynamic profiles to appear does not dirty Git.
- [ ] Repo-managed PowerShell profiles are copied under `%LOCALAPPDATA%\dotfiles\powershell-profiles`.
- [ ] Marker stubs dot-source the local profiles from each intended PowerShell profile path.
- [ ] PowerShell 7 and VS Code load the expected profiles in new processes.
- [ ] Oh My Posh and the selected Git configuration work without unexpected elevation.
- [ ] An existing theme hardlink is converted to an independent file even when hashes match.
      Editing the deployed theme does not change `git diff -- poshthemes`; editing a tracked
      theme does not change the deployed file until setup is applied again.
- [ ] Theme replacements create unique, independent backups. Reapplying matching regular
      files leaves their timestamps/backups unchanged. Copy failures or a locked destination
      preserve the previous file. Test source and target on different volumes when available.
- [ ] A concurrent edit made just before theme publication is retained in an independent
      backup; a destination recreated during publication is never overwritten. Failed recovery
      reports the captured entry for manual review.
- [ ] Setup exits successfully and `git status --short` is empty.

## Interaction 3: idempotency

### Step 9: rerun with an inaccessible repository origin

Record HEAD and the current branch before and after every rerun; both must remain unchanged.
Make the repository origin temporarily inaccessible in the disposable VM and verify that setup
does not attempt fetch/pull or switch branches. Module package/download activity is separate.
For a repeated Git-free invocation, verify that an existing matching branch retains its local HEAD
even if the remote has advanced. A requested different branch must fail before module execution;
select/update it explicitly before retrying. Include an intentionally edited checkout scenario and
verify that tracked/untracked edits and existing bootstrap JSON bytes are preserved by orchestration.

Restore the session variables from step 3. Record hashes and timestamps of the deployed profiles,
themes and host stubs. This function only reads files; backups are excluded by extension.

```powershell
function Get-AcceptanceFileState {
    $Directories = @(
        (Join-Path $env:LOCALAPPDATA 'dotfiles\powershell-profiles'),
        (Join-Path $env:USERPROFILE '.config\oh-my-posh\poshthemes'),
        (Split-Path -Parent $PROFILE.CurrentUserCurrentHost)
    )
    foreach ($Directory in $Directories) {
        Get-ChildItem -LiteralPath $Directory -File -ErrorAction Stop |
            Where-Object Extension -In @('.ps1', '.json') | ForEach-Object {
                [pscustomobject]@{
                    Path = $_.FullName
                    Hash = (Get-FileHash -LiteralPath $_.FullName -ErrorAction Stop).Hash
                    Modified = $_.LastWriteTimeUtc.Ticks
                }
            }
    }
}
$Before = @(Get-AcceptanceFileState)
$Before | Export-Clixml "$EvidenceRoot\04-files-before.xml"
$HeadBefore = git rev-parse HEAD
if ($LASTEXITCODE -ne 0) { throw 'Cannot read HEAD.' }
$BranchBefore = git branch --show-current
if ($LASTEXITCODE -ne 0) { throw 'Cannot read branch.' }
$OriginalOrigin = git remote get-url origin
if ($LASTEXITCODE -ne 0) { throw 'Cannot read origin.' }
try {
    git remote set-url origin 'https://127.0.0.1:1/unavailable.git'
    if ($LASTEXITCODE -ne 0) { throw 'Cannot set the temporary test origin.' }
    & pwsh -NoProfile -File .\setup-scripts\setup.ps1 -NonInteractive
    $RerunExitCode = $LASTEXITCODE
} finally {
    git remote set-url origin $OriginalOrigin
    if ($LASTEXITCODE -ne 0) { throw 'Restore the recorded origin before continuing.' }
}
$RerunExitCode | Set-Content "$EvidenceRoot\04-rerun-exit-code.txt"
if ($RerunExitCode -ne 0) { throw 'Idempotency run failed or requested a reboot.' }
$After = @(Get-AcceptanceFileState)
$Differences = @(Compare-Object -ReferenceObject $Before -DifferenceObject $After -Property Path, Hash, Modified)
$Differences | Format-Table -AutoSize
if ($Differences.Count) { throw 'Deployed content or timestamps changed on an unchanged rerun.' }
$HeadAfter = git rev-parse HEAD
if ($LASTEXITCODE -ne 0 -or $HeadAfter -ne $HeadBefore) { throw 'HEAD changed or is unreadable.' }
$BranchAfter = git branch --show-current
if ($LASTEXITCODE -ne 0 -or $BranchAfter -ne $BranchBefore) { throw 'Branch changed or is unreadable.' }
git status --short
```

Expect no differences, no reboot and no unnecessary UAC. The temporary URL affects only Git's
origin; module package sources remain available. Watch the transcript for forbidden fetch/pull
attempts even if the command exits successfully. The `finally` block restores the original URL.

- [ ] Setup exits successfully without requesting another reboot.
- [ ] No Windows feature module elevation is requested when all features are enabled.
- [ ] Installed packages are skipped rather than reinstalled.
- [ ] No machine installer requests UAC merely because setup was rerun.
- [ ] The existing correct `HOME` junction and user environment variable are left unchanged.
- [ ] Nerd Font files and registry values are not duplicated.
- [ ] Existing Windows Terminal `settings.json`, including dynamic profiles and local edits, is
      not overwritten.
- [ ] Existing PowerShell marker stubs and local profile files converge without duplicate content.
- [ ] User-authored profile files without the dotfiles marker remain untouched.
- [ ] Oh My Posh deployment converges without unnecessary elevation.
- [ ] `git status --short` remains empty.

## Existing-install migration

### Step 10: migrate the production baseline in a separate snapshot

Test this separately from the clean-install snapshot. Start with an installation and local JSON
created by the current `main` branch, including the previous profile and Terminal layout.

Prepare the candidate/evidence state as in step 1 on this VM (using a separate evidence directory
if needed). Do not run the clean-install block. Start in the existing persistent clone, then:

```powershell
Set-Location -LiteralPath $ClonePath
git status --short --branch
$BaselineStatus = @(git status --porcelain)
if ($LASTEXITCODE -ne 0 -or $BaselineStatus.Count) {
    throw 'Use a clean production snapshot; preserve existing tracked/untracked edits before migration.'
}
$BaselineCommit = git rev-parse HEAD
if ($LASTEXITCODE -ne 0) { throw 'Cannot read the production baseline.' }
$BaselineCommit | Set-Content "$EvidenceRoot\06-production-baseline.txt"
git fetch origin
if ($LASTEXITCODE -ne 0) { throw 'Fetch failed.' }
git switch $Branch
if ($LASTEXITCODE -ne 0) { throw 'Cannot select the candidate branch. Preserve any local edits.' }
git merge --ff-only "origin/$Branch"
if ($LASTEXITCODE -ne 0) { throw 'Candidate update is not a fast-forward.' }
$ActualCommit = git rev-parse HEAD
if ($LASTEXITCODE -ne 0 -or $ActualCommit -ne $ExpectedCommit) { throw 'Unexpected migration candidate.' }
$BootstrapPath = '.\dotfiles-configurations\dotfiles-bootstrap-variables.json'
$Bootstrap = Get-Content -LiteralPath $BootstrapPath -Raw | ConvertFrom-Json
$Bootstrap.GITHUB_DOTFILES_BRANCH = $Branch
$Bootstrap | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $BootstrapPath -Encoding utf8
& .\setup-scripts\update.ps1 `
    -NonInteractive -SkipRepositoryUpdate -BackupDirectory "$EvidenceRoot\migration-backups" `
    -TemplateName @('setup-modules.json', 'windows-capabilities.json', 'windows-features.json', 'winget-packages.json') `
    -ErrorAction Stop
```

Review the updated local catalogs before applying. Repository updates above are explicit Git
operations; `update.ps1 -SkipRepositoryUpdate` then updates only the selected catalogs and creates
external backups. Invoke `update.ps1` directly so its array parameter receives four names,
rather than a comma-containing string through native `pwsh -File`. This script throws on failure
and does not exit the console. Keep `$ErrorActionPreference = 'Stop'` from session preparation.

For a baseline that still has selections from `v2026.09.0`, migrate `development` to `dev`,
remove the former default `PowerBI`, and leave the new optional `azure` and `powerbi` groups
absent. Preserve every other selected group and its order:

```powershell
$bootstrapPath = '.\dotfiles-configurations\dotfiles-bootstrap-variables.json'
$bootstrap = Get-Content -LiteralPath $bootstrapPath -Raw | ConvertFrom-Json
$bootstrap.INSTALL_PACKAGES = @($bootstrap.INSTALL_PACKAGES | ForEach-Object {
    if ($_ -ceq 'development') { 'dev' }
    elseif ($_ -cne 'PowerBI') { $_ }
})
$bootstrap | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $bootstrapPath -Encoding utf8
$migratedGroups = @((Get-Content -LiteralPath $bootstrapPath -Raw | ConvertFrom-Json).INSTALL_PACKAGES)
if ($migratedGroups -ccontains 'development' -or $migratedGroups -ccontains 'PowerBI' -or
    $migratedGroups -ccontains 'azure' -or $migratedGroups -ccontains 'powerbi' -or
    $migratedGroups -cnotcontains 'dev') {
    throw "Unexpected migrated package selection: $($migratedGroups -join ', ')."
}
```

Run the step 4 preview command, step 5 apply, step 6 diagnostic and step 9 idempotency check.
Stop/reboot on `3010` as before. Do not apply the clean-install default/opt-in overrides to
the migrated personal selections. Do not repeat the fetch or catalog update between reruns.

- [ ] Every replaced local JSON has a durable backup outside the repository.
- [ ] Identity, endpoint, environment and Git variables are not replaced unless explicitly selected.
- [ ] Invalid templates fail before any selected local file changes.
- [ ] The migrated package selection contains `dev`, contains neither legacy `development` nor
      `PowerBI`, and does not silently opt into `azure` or `powerbi`.
- [ ] Old PowerShell profile symlinks migrate to local profile copies plus marker stubs.
- [ ] User-authored, unmarked profile files are preserved.
- [ ] The old Windows Terminal symlink/tracked layout migrates to an in-place LocalState file.
- [ ] Terminal template refresh shows a diff against the live file.
- [ ] Accepted regeneration moves the live file to backup rather than deleting it.
- [ ] WSL/dynamic profile data can be recovered from that backup.
- [ ] The migrated setup and a subsequent rerun both leave Git clean.

## Repeated Git-free invocation

### Step 11: preserve existing JSON and populate a missing file

This is a distinct safety test, not the post-reboot continuation path. Before running it, put a
recognisable non-secret change in one persistent local JSON and record its content or hash. Move a
different local JSON to a backup outside the repository so the same invocation exercises both the
preserve-existing and populate-missing paths. Take a VM snapshot before changing either file.

Restore the step 3 session variables, then run the following only in this separate snapshot.
The bootstrap JSON already contains the non-default acceptance package selection. Moving the
different catalog below preserves it outside the checkout, rather than deleting it.

```powershell
$PreservedFile = Join-Path $ClonePath 'dotfiles-configurations\dotfiles-bootstrap-variables.json'
$MissingFile = Join-Path $ClonePath 'dotfiles-configurations\windows-features.json'
$MissingBackup = Join-Path $EvidenceRoot '07-windows-features-before-repeat.json'
$BeforeHash = (Get-FileHash -LiteralPath $PreservedFile -Algorithm SHA256).Hash
if (Test-Path -LiteralPath $MissingBackup) { throw 'Use a fresh snapshot/evidence path for this drill.' }
Move-Item -LiteralPath $MissingFile -Destination $MissingBackup -ErrorAction Stop
if (-not (Test-Path -LiteralPath $BootstrapScript -PathType Leaf)) {
    Invoke-WebRequest -UseBasicParsing `
        -Uri "https://raw.githubusercontent.com/abrioso/dotfiles-windows/$ExpectedCommit/setup-scripts/install.ps1" `
        -OutFile $BootstrapScript
}
$InstallArguments = @('-Account', 'abrioso', '-Repo', 'dotfiles-windows', '-Branch', $Branch, '-NonInteractive')
if ($ArchiveSha256) {
    $InstallArguments += @('-Commit', $ExpectedCommit, '-ArchiveSha256', $ArchiveSha256)
}
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
    -NoProfile -File $BootstrapScript @InstallArguments
$RepeatExitCode = $LASTEXITCODE
$RepeatExitCode | Set-Content "$EvidenceRoot\07-repeat-bootstrap-exit-code.txt"
if ($RepeatExitCode -ne 0) { throw 'Repeated bootstrap failed or requested an unexpected reboot.' }
$AfterHash = (Get-FileHash -LiteralPath $PreservedFile -Algorithm SHA256).Hash
if ($AfterHash -cne $BeforeHash) { throw 'Existing local JSON was replaced.' }
if (-not (Test-Path -LiteralPath $MissingFile -PathType Leaf)) { throw 'Missing JSON was not recreated.' }
$TemplateHash = (Get-FileHash -LiteralPath '.\dotfiles-configurations\windows-features.json.example').Hash
if ((Get-FileHash -LiteralPath $MissingFile).Hash -cne $TemplateHash) { throw 'Recreated JSON differs from the candidate template.' }
git status --short
```

Retain the transcript showing both skip/copy messages. Export the evidence and restore the snapshot
before running another scenario; do not treat this bootstrap repetition as post-reboot continuation.

- [ ] Re-run the Git-free bootstrap from the same branch.
- [ ] The existing personalised JSON remains byte-for-byte unchanged.
- [ ] The missing JSON is recreated from the release-branch template.
- [ ] The transcript reports that the existing configuration was skipped and the missing
      configuration was copied.
- [ ] Treat replacement of any existing machine-local JSON as a release blocker.
- [ ] Restore the snapshot before continuing other acceptance tests.

## Backup rollback drill

### Step 12: restore a matching catalog backup and reapply

Use the existing-install migration snapshot and one catalog backup created by `update.ps1`. Record
the current migrated file hash, restore its matching backup, and verify that the restored bytes
exactly match the backup. Parse the restored JSON before using it. Then rerun `update.ps1`, repeat
the documented package-selection migration when applicable, and run `setup.ps1` twice to return to
the release-candidate state.

```powershell
$CatalogPath = '.\dotfiles-configurations\winget-packages.json'
Get-ChildItem -LiteralPath "$EvidenceRoot\migration-backups" -Recurse -File | Select-Object FullName
$CatalogBackup = Read-Host 'Absolute path of the matching winget-packages.json backup'
if (-not (Test-Path -LiteralPath $CatalogBackup -PathType Leaf)) { throw 'Backup is unavailable.' }
Get-Content -LiteralPath $CatalogBackup -Raw | ConvertFrom-Json -ErrorAction Stop | Out-Null
$MigratedHash = (Get-FileHash -LiteralPath $CatalogPath -Algorithm SHA256).Hash
$BackupHash = (Get-FileHash -LiteralPath $CatalogBackup -Algorithm SHA256).Hash
Copy-Item -LiteralPath $CatalogBackup -Destination $CatalogPath -Force
$RestoredHash = (Get-FileHash -LiteralPath $CatalogPath -Algorithm SHA256).Hash
if ($RestoredHash -cne $BackupHash) { throw 'Restored catalog does not match its backup.' }
Get-Content -LiteralPath $CatalogPath -Raw | ConvertFrom-Json -ErrorAction Stop | Out-Null
[pscustomobject]@{ Migrated = $MigratedHash; Backup = $BackupHash; Restored = $RestoredHash } |
    ConvertTo-Json | Set-Content "$EvidenceRoot\08-rollback-hashes.json"
& .\setup-scripts\update.ps1 `
    -NonInteractive -SkipRepositoryUpdate -BackupDirectory "$EvidenceRoot\rollback-backups" `
    -TemplateName winget-packages.json -ErrorAction Stop
```

Repeat the applicable legacy selection migration from step 10, then step 5 apply and step 9
idempotency, respecting reboot boundaries. Export the evidence before restoring the snapshot.

- [ ] The pre-rollback migrated hash, backup hash and restored hash are recorded.
- [ ] The restored file matches the durable backup byte-for-byte and remains valid JSON.
- [ ] Reapplying the catalog update and package-selection migration succeeds.
- [ ] Two subsequent setup runs converge successfully and leave the tracked tree clean.
- [ ] Restore the migration snapshot after the drill.

## Final release-branch gate

### Step 13: record the verdict

```powershell
if (-not (Test-Path -LiteralPath "$EvidenceRoot\acceptance.md")) {
    Copy-Item -LiteralPath '.\docs\RELEASE_EVIDENCE_TEMPLATE.md' -Destination "$EvidenceRoot\acceptance.md"
}
notepad (Join-Path $EvidenceRoot 'acceptance.md')
```

Fill in the exact tested commit, Windows build, transcript paths, exit codes and manual observations.
Only mark PASS after the full required matrix passes;
scope mismatch, source failures, edited checkouts, theme-link/failure/concurrency scenarios and
unavailable Entra ID/OneDrive/cross-volume checks still need their own recorded evidence or an
explicitly accepted limitation. CI or successful command parsing alone does not establish this.

- [ ] All required scenarios pass against the exact `release/vYYYY.MM.N` commit.
- [ ] The release PR targets `main` and the required `powershell` check succeeds.
- [ ] The release PR is merged with a merge commit.
- [ ] Any release-only stabilization commits are reconciled from the same release branch into
      `develop` through a second merge-commit PR.
- [ ] The `vYYYY.MM.N` tag points to the verified merge commit on `main`.
- [ ] The matching GitHub Release is published with tested Windows build and known limitations.
- [ ] The release branch is deleted only after both branches, tag and release are verified.
