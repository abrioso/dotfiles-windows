# Release testing

This checklist is the acceptance gate for promoting `develop` through a
`release/vYYYY.MM.N` branch into `main`. Record the tested commit, Windows build, machine type,
and evidence for every required scenario.

## Test topology

Use a disposable Windows 11 Pro or Enterprise machine or VM with snapshots. An Entra ID joined
machine whose real profile path contains non-ASCII characters is required for the `HOME` alias
scenario. Use the default package, feature, capability, and setting selections unless a scenario
says otherwise. Tailscale and Google Drive remain opt-in; select both explicitly for the package
acceptance scenario without adding them to the tracked defaults.

The three main interactions do **not** all use the Git-free entry point:

1. **Clean install:** start with the Git-free bootstrap from Windows PowerShell 5.1.
2. **Post-reboot continuation:** run `setup.ps1` from the persistent workspace clone.
3. **Idempotency:** run `setup.ps1` from the same persistent clone again.

The Git-free archive is a bootstrap transport, not the persistent checkout. Re-running it creates
fresh local JSON from the archive templates and currently copies those files into the persistent
clone with replacement semantics. Do not use it for post-reboot continuation when preserving the
first run's local choices matter. Test repeated Git-free invocation separately as described below.

## Evidence to capture

For each interaction, retain:

- the exact Git commit under test;
- the setup transcript and any elevated Windows feature or capability transcript;
- the process exit code;
- screenshots or command output for UAC, WSL, Docker, package and filesystem checks;
- `git status --short` from the persistent clone.

Never publish transcripts or configuration backups before checking them for usernames, email
addresses, repository endpoints, tokens, or other machine-specific values.

## Interaction 1: clean Git-free install

### Preconditions

- Start from a snapshot with the selected Windows optional features disabled and capabilities absent.
- Remove any previous persistent dotfiles clone, local dotfiles configuration, `HOME` alias,
  Windows Terminal baseline, and repo-managed PowerShell profiles.
- Ensure Windows Package Manager is available. Git and PowerShell 7 should be absent when testing
  prerequisite installation.
- Start from the in-box Windows PowerShell 5.1 host, not `pwsh`.

Allow user-scoped scripts:

```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
```

Run the `develop` Git-free bootstrap during pre-release testing:

```powershell
iex "& { $(irm 'https://raw.githubusercontent.com/abrioso/dotfiles-windows/develop/setup-scripts/install.ps1') } -Account abrioso -Repo dotfiles-windows -Branch develop -NonInteractive"
```

For the final release-candidate retest, replace `develop` in both URL and `-Branch` with the exact
`release/vYYYY.MM.N` branch.

### Acceptance checks

- [ ] The archive downloads and its extracted root is resolved correctly.
- [ ] Local JSON configuration is created from the selected branch templates.
- [ ] Missing `Microsoft.PowerShell` and `Git.Git` prerequisites install successfully with user
      scope; PowerShell uses its MSIX package rather than the MSI/WiX installer.
- [ ] PATH refresh makes both `pwsh` and `git` available to the running bootstrap.
- [ ] Windows PowerShell 5.1 relaunches setup in PowerShell 7 before repository Git operations.
- [ ] The persistent clone is created under the configured workspace.
- [ ] The clone checks out the requested `develop` or `release/vYYYY.MM.N` branch and its HEAD is
      the expected commit.
- [ ] Local gitignored JSON from the bootstrap copy reaches the persistent clone.
- [ ] The Windows feature module runs under Windows PowerShell 5.1 and requests elevation once.
- [ ] Enabling the selected features returns exit code `3010` when a reboot is required.
- [ ] The Git-free wrapper returns the same `3010` exit code.
- [ ] Package modules after the Windows feature boundary do not run before reboot. Bootstrap
      prerequisites are expected; WSL, Ubuntu, Docker and settings are not.
- [ ] Both the main and elevated module transcript paths are reported and the files exist.
- [ ] No tracked file in the persistent clone is modified.

Restart Windows before interaction 2.

## Interaction 2: post-reboot continuation

Open PowerShell in the persistent clone. Before the first post-reboot setup run, launch the TUI and
add the opt-in `tailscale` and `google-drive` package groups while preserving the other default
selections:

```powershell
.\setup-scripts\configure.ps1
$bootstrap = Get-Content -LiteralPath '.\dotfiles-configurations\dotfiles-bootstrap-variables.json' -Raw | ConvertFrom-Json
foreach ($group in @('tailscale', 'google-drive')) {
    if ($group -notin @($bootstrap.INSTALL_PACKAGES)) {
        throw "Required acceptance package group '$group' is not selected."
    }
}
```

Then run setup from the same persistent clone:

```powershell
git status --short --branch
git rev-parse HEAD
.\setup-scripts\setup.ps1
```

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
- [ ] No package reports `No applicable installer`, `0x8A150010`, hash mismatch, or an ignored
      non-zero Winget exit code.
- [ ] `Microsoft.PowerShell` and `Microsoft.WindowsTerminal` remain user-scoped MSIX packages.
- [ ] Packages declared with machine scope request UAC only when installation is required.
- [ ] With the opt-in `tailscale` and `google-drive` groups selected, both packages install using
      their machine-scoped installers and are detected as installed on the idempotency run.
- [ ] `Microsoft.WSL` installs before `Canonical.Ubuntu`, and the WSL group completes before
      Docker Desktop.

### WSL and Docker checks

```powershell
wsl --version
wsl --status
wsl --list --verbose
docker run --rm hello-world
```

- [ ] WSL commands complete successfully.
- [ ] Ubuntu is registered as WSL version 2, or its not-yet-registered state is reported clearly
      with WSL 2 set as the default for first launch.
- [ ] Docker Desktop uses the intended backend and `hello-world` succeeds.

### User and terminal settings checks

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
- [ ] Setup exits successfully and `git status --short` is empty.

## Interaction 3: idempotency

Without changing configuration, run from the same persistent clone:

```powershell
.\setup-scripts\setup.ps1
git status --short
```

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

Test this separately from the clean-install snapshot. Start with an installation and local JSON
created by the current `main` branch, including the previous profile and Terminal layout.

1. In `dotfiles-configurations\dotfiles-configuration.json`, set `GITHUB_DOTFILES_BRANCH` to
   `develop` or the release branch. Then, from inside the persistent clone, run:
   ```
   git fetch origin
   git checkout <branch>
   ```
2. Run `setup-scripts\update.ps1` and select only the shared catalogs initially:
   `setup-modules.json`, `windows-capabilities.json`, `windows-features.json`, and
   `winget-packages.json`.
3. Review the new local JSON before running setup.
4. Run `setup.ps1`, then run it again to prove the migrated state is idempotent.

- [ ] Every replaced local JSON has a durable backup outside the repository.
- [ ] Identity, endpoint, environment and Git variables are not replaced unless explicitly selected.
- [ ] Invalid templates fail before any selected local file changes.
- [ ] Old PowerShell profile symlinks migrate to local profile copies plus marker stubs.
- [ ] User-authored, unmarked profile files are preserved.
- [ ] The old Windows Terminal symlink/tracked layout migrates to an in-place LocalState file.
- [ ] Terminal template refresh shows a diff against the live file.
- [ ] Accepted regeneration moves the live file to backup rather than deleting it.
- [ ] WSL/dynamic profile data can be recovered from that backup.
- [ ] The migrated setup and a subsequent rerun both leave Git clean.

## Repeated Git-free invocation

This is a distinct safety test, not the post-reboot continuation path. Before running it, put a
recognisable non-secret change in one persistent local JSON and take a snapshot or backup.

- [ ] Re-run the Git-free bootstrap from the same branch.
- [ ] Record whether the persistent local JSON is preserved, replaced, or prompts for a decision.
- [ ] Treat silent replacement of existing machine-local choices as a release blocker unless it is
      explicitly accepted and documented for that release.
- [ ] Restore the snapshot before continuing other acceptance tests.

## Final release-branch gate

- [ ] All required scenarios pass against the exact `release/vYYYY.MM.N` commit.
- [ ] The release PR targets `main` and the required `powershell` check succeeds.
- [ ] The release PR is merged with a merge commit.
- [ ] Any release-only stabilization commits are reconciled from the same release branch into
      `develop` through a second merge-commit PR.
- [ ] The `vYYYY.MM.N` tag points to the verified merge commit on `main`.
- [ ] The matching GitHub Release is published with tested Windows build and known limitations.
- [ ] The release branch is deleted only after both branches, tag and release are verified.
