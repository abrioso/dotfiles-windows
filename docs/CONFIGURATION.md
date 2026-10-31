# Configuration

This repository separates tracked defaults from machine-specific configuration.

## File model

Tracked templates live in `dotfiles-configurations/` with a `.json.example` suffix:

| Template | Local file created by the TUI | Purpose |
| --- | --- | --- |
| `dotfiles-bootstrap-variables.json.example` | `dotfiles-bootstrap-variables.json` | Bootstrap settings, repository endpoint type, install groups, and workspace path. |
| `winget-packages.json.example` | `winget-packages.json` | Available `winget` package groups and package IDs. |
| `windows-features.json.example` | `windows-features.json` | Available Windows optional feature groups and feature names. |
| `windows-capabilities.json.example` | `windows-capabilities.json` | Available Windows capability groups and capability names. |
| `setup-modules.json.example` | `setup-modules.json` | Ordered setup module plan for features, capabilities, packages, and settings. |
| `env-variables.json.example` | `env-variables.json` | Environment variables to apply. |
| `git-variables.json.example` | `git-variables.json` | Global Git configuration values. |

Local `*.json` files are intentionally ignored by Git. Commit changes to `*.json.example` only when you want to change shared defaults for everyone.

## Creating local configuration

Run the configuration TUI before setup, or let `setup.ps1` launch it automatically when local config files are missing:

```pwsh
.\setup-scripts\configure.ps1
```

For non-interactive bootstrap flows, the TUI can create local files from templates without prompts:

```pwsh
.\setup-scripts\configure.ps1 -NonInteractive
```

The TUI automatically adds package groups required by selected setting groups. Setup validates the same dependency metadata before running any module, including when local JSON files are edited manually.

## Setup preflight

`setup.ps1` validates configuration before installing PowerShell/Git prerequisites or requesting
elevation. Missing local files are still initialized by the configuration TUI first. The persistent
clone is validated again after local checkout selection and configuration synchronization, before module execution.

The preflight requires JSON objects for all seven local configuration files and checks:

- non-empty string values for `WORKSPACE_FOLDER`, `GITHUB_ACCOUNT`, and `GITHUB_DOTFILES_REPO`;
- supported repository endpoint settings;
- selectors against their package, feature, capability and setting catalogs;
- package ID syntax, supported `scope`/`installerType` metadata, and conflicting duplicate
  package declarations across selected groups (IDs are compared case-insensitively);
- module arrays, existing `.ps1` filenames without directory components, boolean `requiresAdmin`,
  valid selectors, and package dependencies;
- scalar Git setting values and valid environment entries with `User` or `Machine` scope.

Unknown selections, such as `bsae` instead of `base`, fail with the available group names.
Explicit empty selector arrays mean "select nothing". Missing selectors retain the legacy
defaults; single-string selectors and package ID strings remain supported. Fix invalid files
and rerun setup; preflight does not install or apply machine settings. It validates declarations,
not whether a package exists in the remote WinGet source or a feature is available on this OS.

## Installed-state diagnostic

After applying setup, diagnose the selected state from this checkout in PowerShell 7.2 or later:

```powershell
.\setup-scripts\verify.ps1
.\setup-scripts\verify.ps1 -Format Json
.\setup-scripts\verify.ps1 -Format Json -CheckPackages
```

The command validates existing local configuration using the same preflight and selection resolver
as setup. It does not initialize configuration, update the checkout, apply modules, request elevation,
start transcripts or save reports. It checks executable availability, selected Windows features and
capabilities, persistent environment values, global Git values, profile copies and portable stubs,
theme content and Terminal settings. Profiles are checked for the invoking PowerShell host only.
Selected capabilities in `NotPresent` or `Staged` state are `Drift`; pending states remain `Unknown`.
WinGet executable availability is checked only when the package installation module is selected,
independently of the optional `-CheckPackages` presence queries.
Terminal settings only need to exist and parse as JSON: setup preserves local customizations.
Readable empty or malformed settings are `Drift`; access and read failures remain `Unknown`.
User-authored profiles are skipped because setup intentionally preserves them.
The console and VS Code entry points share `powershell-profiles/common.ps1`.
All `.ps1` files in that directory are copied into the machine-local store; only
`*_profile.ps1` and `profile.ps1` entry points receive portable Documents stubs.
The diagnostic checks support-file copies too, without expecting stubs for them.
Existing user-authored profiles are not automatically connected to the shared file.
No additional support file, including ignored `extra.ps1`, is sourced automatically.
Reapply removes unmodified portable support-file stubs created by older installers,
even for optional source files that no longer exist. User-authored files, edited
stubs and links remain untouched for manual review. The diagnostic reports remaining
marker-owned support stubs as drift instead of ignoring them.

Each check has one of four statuses:

| Status | Meaning |
| --- | --- |
| `Passed` | The stated check succeeded; this is not a complete certification of setup. |
| `Drift` | A difference or missing required artifact was confirmed. |
| `Unknown` | State could not be established, including permissions, unsupported OS components or unavailable probes. |
| `Skipped` | The apply contract intentionally excludes this item. |

Exit codes are `0` for passed/skipped checks only, `1` if any drift was found, and `2` if
checks are inconclusive without confirmed drift. Invalid configuration produces an inconclusive
report and prevents state probes. JSON includes `SchemaVersion`, `Checks`, `Counts`, `ExitCode`
and `Limitations`. Environment and Git checks use anonymous labels and never report configured
or observed values, personal paths, repository endpoints, native stderr or exception details.
Component IDs and source filenames remain visible.
Git and environment value comparisons are case-sensitive. Existing apply modules compare values
case-insensitively, so a case-only difference may require a manual correction.

WinGet presence checks require `-CheckPackages`: native WinGet may contact package sources and
write its own cache/logs. The diagnostic never accepts source agreements or installs/updates packages.
A failed query is inconclusive, not evidence of absence. A successful exact-ID query does not verify
requested scope or installer type; those constraints remain `Unknown`. Package versions are not
constrained by the current catalog. Native queries time out after 15 seconds per item.

This first diagnostic does not probe Nerd Font registration, HOME alias correctness or WSL distro
state. Selected modules without probes are explicitly `Unknown`. With default selections and without
package opt-in, expect an inconclusive report even when the implemented checks pass. Use the check
messages to assess coverage; do not treat `Unknown` as a successful installation.

## Setup plan

Create or edit local JSON with `setup-scripts\configure.ps1`, then preview the invoked checkout:

```pwsh
.\setup-scripts\setup.ps1 -Plan
.\setup-scripts\setup.ps1 -Plan -PlanFormat Json
.\setup-scripts\setup.ps1 -Plan -BootstrapBranch develop
```

`-Plan` validates all seven existing local files using the setup preflight and reuses the same
module resolver as apply. Missing files or invalid configuration fail with exit code `1`; missing
files are never generated, even with `-NonInteractive`. Success returns exit code `0`.
No transcript, configuration write, prerequisite installation, Git operation, network request,
UAC prompt, module execution or automatic PowerShell relaunch occurs. `-LogFilePath` and
`-AppendLog` have no effect in plan mode. `-BootstrapBranch` changes only the preview's branch,
without saving it or reading that branch's remote contents. `-PlanFormat` requires `-Plan`.

Text output lists groups, expanded features/capabilities, unique packages in catalog order,
scope and installer type, and ordered modules. JSON output is a single object with `SchemaVersion`,
`Source`, `Branch`, `Limitations`, `Selections`, `Features`, `Capabilities`, `Packages` and `Modules`.
Collection fields remain arrays when empty or containing one item. Module entries include
`Order`, `Script`, `RequiresAdmin` (catalog declaration), `Elevation` and `MayRequireRestart`.
Personal Git values, environment values, workspace paths and repository URLs are omitted.

This is a declaration preview, not an installed-state check: it does not determine which packages
or Windows components are already present, whether an OS feature/package is available, or whether
a reboot is currently pending. Elevation is conditional; setup may skip already satisfied Windows
components and home aliases, while package installers and pending Machine environment changes
may request it independently of the module catalog. Restart flags identify known potential
requirements; custom modules can introduce others.

Apply uses the invoked Git working tree, or prepares the persistent clone from a Git-free transport,
and reloads its saved configuration before resolving modules. Setup does not fetch, pull or switch
existing branches. Existing persistent choices can still change a transport's previewed module plan.
The preview's `Branch` is a declared bootstrap preference, not a verification of local Git HEAD.
For later runs, preview from the persistent clone that holds your machine's configuration.
Missing selectors retain apply's legacy defaults (all feature/package/setting groups, no capabilities);
explicit empty arrays opt out, and scalar selectors remain supported. Package IDs are deduplicated
case-insensitively; conflicting metadata fails in preflight. Planning does not export an executable
or locked plan for a later apply.

## Updating the checkout and local JSON files

Repository updating and configuration application are separate operations. For a repository-only
fast-forward followed by a preview and apply from the same checkout:

```powershell
.\setup-scripts\update.ps1 -NonInteractive -UpdateRepository
.\setup-scripts\setup.ps1 -Plan
.\setup-scripts\setup.ps1
```

This updater invocation changes no local JSON because it names no templates. It refuses tracked
changes, detached HEAD or a non-fast-forward; setup itself can apply an intentionally edited working
tree or detached commit when no `-BootstrapBranch` is requested. Review local edits before applying.

Run the updater when new shared templates are available:

```pwsh
.\setup-scripts\update.ps1
```

It first asks whether the current Git branch should be updated with `git pull --ff-only`. It then asks independently which clean, Git-tracked `*.json.example` templates should replace their local, gitignored `*.json` counterparts. Untracked or locally modified templates are rejected. No setup module is executed, so this operation alone does not install packages, enable Windows features, or apply settings.

By default, the updater recommends only shared catalogs that do not contain user identity or machine endpoint values:

- `setup-modules.json`
- `windows-capabilities.json`
- `windows-features.json`
- `winget-packages.json`

The remaining templates are still selectable, but are marked as containing user or machine variables:

- `dotfiles-bootstrap-variables.json`
- `env-variables.json`
- `git-variables.json`

Use the compact, numbered multi-selection TUI with:

```pwsh
.\setup-scripts\update.ps1 -Tui
```

Existing local files are backed up under `%LOCALAPPDATA%\dotfiles-windows\config-backups\<timestamp>` before replacement. If `LOCALAPPDATA` is unavailable, the fallback is `~\.dotfiles-windows\config-backups\<timestamp>`. Backups may contain personal values and should be retained only as long as needed. Invalid template JSON is rejected before any local file is changed. If a later filesystem operation fails, earlier replacements from that invocation are rolled back; a rollback failure is reported explicitly with the affected filename. Review the resulting JSON before running `setup.ps1`.

For an explicit unattended update, name every local JSON that may be replaced:

```pwsh
.\setup-scripts\update.ps1 `
    -NonInteractive `
    -UpdateRepository `
    -TemplateName winget-packages.json,windows-capabilities.json,windows-features.json,setup-modules.json
```

In non-interactive mode the repository is updated only when `-UpdateRepository` is present, and no JSON is replaced unless named with `-TemplateName`.

### Regenerating Windows Terminal settings

Windows Terminal `settings.json` is generated directly into the Terminal package LocalState by `setup.ps1`; there is no local copy in `dotfiles-configurations/`. When you refresh `windows-terminal-settings.json.example` through the updater, it first shows a diff between the updated template and the live file. If you then accept regeneration, the live `settings.json` is **moved into the backup directory** (not deleted) so machine-specific content — WSL or other dynamic profiles, custom fragments — can be recovered; the next `setup.ps1` run regenerates the file from the updated baseline. In non-interactive mode nothing is moved unless `-RegenerateTerminalSettings` is passed:

```pwsh
.\setup-scripts\update.ps1 `
    -NonInteractive `
    -SkipRepositoryUpdate `
    -TemplateName windows-terminal-settings.json `
    -RegenerateTerminalSettings
```

## Repository endpoint types

`dotfiles-bootstrap-variables.json` supports these endpoint types:

| `REPOSITORY_ENDPOINT_TYPE` | Result |
| --- | --- |
| `github-https` | Clone with `https://github.com/<account>/<repo>.git`. |
| `github-ssh` | Clone with `git@github.com:<account>/<repo>.git`. |
| `custom` | Clone from `CUSTOM_REPOSITORY_URL`. |

Examples:

```json
{
  "REPOSITORY_ENDPOINT_TYPE": "github-https",
  "GITHUB_ACCOUNT": "abrioso",
  "GITHUB_DOTFILES_REPO": "dotfiles-windows"
}
```

```json
{
  "REPOSITORY_ENDPOINT_TYPE": "custom",
  "CUSTOM_REPOSITORY_URL": "https://git.example.com/team/dotfiles-windows.git"
}
```

## Package group selection

`INSTALL_PACKAGES` in `dotfiles-bootstrap-variables.json` controls which package groups are installed from `winget-packages.json`.

The tracked defaults deliberately leave `azure`, `powerbi`, `tailscale`, `delinea`, `yubico`
and `google-drive` unselected. These are optional toolsets or integrations: add any required group
to `INSTALL_PACKAGES` through the TUI or local JSON.

Package object entries contain an `id` and may constrain `scope` (`user` or `machine`) and
`installerType` (currently `wix`). Omit scope when the selected upstream manifest does not declare
one; forcing a scope is an installer-selection constraint and can result in `No applicable
installer`. Duplicate package IDs across selected groups must use identical metadata.

```json
{
  "INSTALL_PACKAGES": [
    "base",
    "dev",
    "wsl"
  ]
}
```

An explicit empty array means **install no package groups**:

```json
{
  "INSTALL_PACKAGES": []
}
```

If `INSTALL_PACKAGES` is absent and no groups are passed directly to `Install-WingetPackages.ps1`, the module falls back to installing all package groups.

## Windows feature group selection

`INSTALL_FEATURES` controls which Windows optional feature groups are enabled from `windows-features.json`.

```json
{
  "INSTALL_FEATURES": [
    "hyperv",
    "wsl"
  ]
}
```

An explicit empty array skips Windows optional feature configuration. If the property is absent, setup preserves the old behavior and enables all feature groups from the feature catalog.

The shared `wsl` feature group targets WSL 2 only and enables `VirtualMachinePlatform`. The modern `Microsoft.WSL` runtime and Ubuntu distribution are installed separately through Winget; the legacy `Microsoft-Windows-Subsystem-Linux` component used for WSL 1 is not enabled on clean installations. After package installation, `Configure-WSL2.ps1` sets version 2 as the default and converts an existing `Ubuntu` registration to WSL 2.

`Configure-WindowsFeatures.ps1` and `Configure-WindowsCapabilities.ps1` run under the in-box Windows PowerShell 5.1 host even when the main setup is running in PowerShell 7. This avoids the known `Class not registered` failure in DISM PowerShell cmdlets hosted by MSIX/WindowsApps builds of PowerShell 7; all other setup modules continue to use PowerShell 7.

Before requesting elevation, setup performs a read-only `Win32_OptionalFeature` CIM preflight. If every requested feature is present exactly once with `InstallState = 1` (`Enabled`), the administrative module is skipped. Any disabled, absent, unknown, duplicate, missing, or unqueryable state falls back to the elevated module, which revalidates the selection with DISM before making changes.

If enabling a selected Windows feature requires a reboot, setup exits with Windows code `3010` before installing packages or applying settings. Restart Windows and run setup again; the feature module skips features that are already enabled and setup continues with the remaining modules.

## Windows capability group selection

`INSTALL_CAPABILITIES` controls which Windows capability groups are installed from `windows-capabilities.json`.

```json
{
  "INSTALL_CAPABILITIES": [
    "rsat-active-directory"
  ]
}
```

An explicit empty array skips Windows capability configuration. Because capabilities were added after the original configuration format, an absent property also skips them; existing machines therefore do not begin installing new capabilities merely because their checkout was updated.

The `rsat-active-directory` group installs `Rsat.ServerManager.Tools~~~~0.0.1.0` before `Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0`, preserving the prerequisite-before-dependent order. `Configure-WindowsCapabilities.ps1` skips capabilities in the `Installed` state and calls `Add-WindowsCapability` for the installable `NotPresent` and `Staged` states. Unknown states and unavailable capability names fail the module instead of being silently skipped.

Like the Windows feature module, the capability module uses the in-box Windows PowerShell 5.1 host for DISM cmdlets, owns an independent log, and returns code `3010` when Windows reports that a reboot is required. It immediately defers any remaining capabilities so dependent components are not installed across a pending restart; restart Windows and run setup again to continue. Its read-only preflight fails closed: if capability state cannot be established without elevation, setup runs the administrative module, which validates the state again before making changes.

Local configuration files are intentionally preserved once created. When upgrading an existing checkout, reconcile `windows-capabilities.json`, `windows-features.json`, `winget-packages.json`, `dotfiles-bootstrap-variables.json`, and `setup-modules.json` with their updated `.example` templates before testing this flow. The setup does not automatically disable an already enabled `Microsoft-Windows-Subsystem-Linux` component because another local distro may still depend on WSL 1; verify all distros with `wsl --list --verbose` before disabling that legacy feature manually.

## Setup setting group selection

`INSTALL_SETTINGS` controls which setting modules are run from `setup-modules.json`.

```json
{
  "INSTALL_SETTINGS": [
    "base",
    "developer",
    "pwsh"
  ]
}
```

An explicit empty array skips setting modules. If the property is absent, setup preserves the old behavior and runs all setting groups from the module catalog.

## Git-free install parameters

`setup-scripts/install.ps1` can be parameterized instead of edited:

```pwsh
iex "& { $(irm 'https://raw.githubusercontent.com/YourGitHubAccount/YourDotfilesRepoName/main/setup-scripts/install.ps1') } -Account YourGitHubAccount -Repo YourDotfilesRepoName -Branch main"
```

The `-Branch` value selects the downloaded archive and the initial clone branch. For an existing
clone it is a requirement, not permission to switch or update the branch. A mismatch, including
detached HEAD, stops setup with instructions to select the branch explicitly. The selected initial
branch is saved only when the clone is newly created; existing saved preferences are preserved.

After the Git-free bootstrap creates the persistent workspace clone, post-reboot continuation and
normal reruns should execute `setup-scripts\setup.ps1` from that clone. A new Git-free invocation
extracts a fresh archive and recreates missing local JSON there. Synchronization copies only JSON
missing from the persistent clone and preserves existing machine-local files. Setup then reloads
that clone's bootstrap variables before planning modules. `-Branch` verifies the existing clone's
branch without changing its HEAD or saved branch preference. Repository location and endpoint
selection use transport configuration only for Git-free invocation. In a Git checkout (including
a worktree), setup uses the invoked root rather than another configured workspace directory.
The saved branch preference does not redirect normal local apply; an explicit `-BootstrapBranch`
must match the local branch. Use `update.ps1` to refresh code before applying new templates/modules.
The release acceptance matrix tests preservation and missing-file population separately; see
[Release testing](RELEASE_TESTING.md#repeated-git-free-invocation).

For an unattended bootstrap that accepts all template defaults:

```pwsh
iex "& { $(irm 'https://raw.githubusercontent.com/YourGitHubAccount/YourDotfilesRepoName/main/setup-scripts/install.ps1') } -Account YourGitHubAccount -Repo YourDotfilesRepoName -Branch main -NonInteractive"
```

For a custom ZIP archive endpoint:

```pwsh
iex "& { $(irm 'https://example.com/install.ps1') } -EndpointType custom-archive -ArchiveUrl https://example.com/dotfiles.zip"
```

The installer resolves the extracted root dynamically, so custom archives do not need to use GitHub's `<repo>-<branch>` folder naming convention.

## Bootstrap behaviour

During setup:

1. Missing Git and PowerShell prerequisites use the scope and installer type declared in the selected local package groups. Shared defaults request machine scope for Git (potentially requesting UAC while the bootstrap itself stays in the invoking user's context) and user scope for PowerShell. If a prerequisite is absent from the selected groups, bootstrap still installs it using those fallback scopes. Legacy strings and objects without scope remain unscoped. Existing commands are reused without scope migration; later package checks still enforce the selected catalog's scope.
2. A bootstrap started from Windows PowerShell 5.1 relaunches itself in PowerShell 7 before running Git commands.
3. Missing local config files are created from the `.json.example` templates.
4. A Git invocation selects its current checkout. A Git-free invocation creates the missing persistent clone using the selected endpoint and branch.
5. Existing checkouts retain HEAD, branch and local edits; no fetch, checkout, switch or pull is performed. Explicit branch requirements are verified locally and a mismatch stops setup.
6. Local gitignored configuration generated during Git-free bootstrap populates only missing files in the persistent clone. A newly cloned branch override is saved there; existing saved files are preserved.
7. Setup validates package-group dependencies declared by selected settings.
8. Setup builds an ordered module plan from `setup-modules.json` and the selected `INSTALL_FEATURES`, `INSTALL_CAPABILITIES`, `INSTALL_PACKAGES`, and `INSTALL_SETTINGS` values.
9. Setup modules consume the local `*.json` files and setup stops if a configured module is missing or fails.

### Theme deployment

The `pwsh` setting deploys Oh My Posh themes as independent copies without elevation. Copies are
staged in the destination directory, checked with SHA-256 and published by rename; the final
file is checked again. A matching regular file is left untouched. Legacy hardlinks and file
symlinks are replaced even when their contents match, so editing a deployed theme cannot edit
the tracked file. Existing content is first retained in a unique `<theme>.<guid>.bak` regular
file; earlier backups, including old `.bak` files, are not overwritten.

Updating Git does not automatically update the deployed copy: apply setup again to adopt theme
changes. As before, local edits to a managed theme are backed up and replaced on apply. Keep a
separately named, unmanaged theme if you want to retain customizations permanently; untracked
theme names are not removed. No automatic backup cleanup is performed.

Linked destination directories require manual review because they can redirect writes into the
checkout. Broken or unreadable file links also fail without replacement. Copy, verification or
publication failures stop the module; staged files are cleaned up and completed backups remain.
Publication is per file, not a transaction across the complete theme set. Inspect the retained
backup if final verification fails after publication. No migration runs until setup is applied.

At publication, the previous directory entry is first renamed to a unique `.captured.bak`.
The staged copy is then renamed into place without overwriting an entry created by another
writer. A brief filename gap can occur between these renames. On failure the previous entry
is restored only when the destination is still absent; otherwise it remains captured and the
competing destination is preserved. Edits captured after the initial backup are copied into
an additional independent backup under a read handle that denies writes. Captured entries are
removed only after their contents are independently retained. A captured artifact left by a
failure may retain legacy link metadata: copy its bytes before editing it or restoring it.

Before migrating a legacy hardlink, review `git diff -- poshthemes`: edits made through that link
may already be present in the checkout. Migration detaches the current source bytes and does not
restore upstream contents or discard uncommitted edits. `verify.ps1` reports linked themes as
`Drift`, even when hashes match.

The CaskaydiaCove Nerd Font is installed by the `base` settings group, since it is required for
terminal rendering regardless of the Oh My Posh selection.
