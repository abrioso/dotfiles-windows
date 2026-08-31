# User install journey

This document describes the end-user installation flow implemented by the `develop` branch code.

## 1. Prepare PowerShell

Before running setup, allow user-scoped script execution:

```pwsh
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
```

## 2. Choose an entry point

### Clone and run locally

```pwsh
git clone https://github.com/abrioso/dotfiles-windows.git
cd dotfiles-windows
.\setup-scripts\configure.ps1
.\setup-scripts\setup.ps1
```

### Git-free bootstrap

```pwsh
iex ((New-Object Net.WebClient).DownloadString('https://raw.githubusercontent.com/abrioso/dotfiles-windows/main/setup-scripts/install.ps1'))
```

The Git-free path downloads a ZIP archive into `%TEMP%\dotfiles`, extracts it, and launches `setup.ps1` from the extracted folder.

The archive is the initial bootstrap transport. Once setup creates the persistent workspace clone,
post-reboot continuation and later idempotency runs execute `setup.ps1` from that clone rather than
downloading a new archive. A repeated Git-free invocation has separate local-configuration
replacement semantics documented in [Configuration](CONFIGURATION.md#git-free-install-parameters)
and is tested independently in [Release testing](RELEASE_TESTING.md#repeated-git-free-invocation).

## 3. Local configuration is created

The setup flow expects local machine-specific JSON files in `dotfiles-configurations/`. If they do not exist, `setup-scripts/configure.ps1` creates them from the tracked templates:

- `dotfiles-bootstrap-variables.json.example`
- `git-variables.json.example`
- `env-variables.json.example`
- `winget-packages.json.example`
- `windows-features.json.example`
- `windows-capabilities.json.example`
- `setup-modules.json.example`

These local `*.json` files are gitignored and are intended to hold machine-specific values.

## 4. The user configures the install

In interactive mode, `configure.ps1` prompts for the main install choices:

- repository endpoint type (`github-https`, `github-ssh`, or `custom`)
- GitHub account, repository, and bootstrap branch
- workspace folder under `%USERPROFILE%`
- package groups to install
- Windows feature groups to enable
- Windows capability groups to install
- settings groups to apply
- Git identity and editor settings

If `-NonInteractive` is used, the setup accepts the defaults from the `*.json.example` templates.

## 5. Bootstrap prerequisites are installed

`setup.ps1` installs the prerequisites needed to continue:

- `Microsoft.PowerShell`
- `Git.Git`

Both are installed with `winget` for the current user when missing. On the current `develop` flow, `winget` is required for bootstrap.

## 6. PATH is refreshed

After installing prerequisites, the setup refreshes the current process PATH from the machine and user PATH values so that newly installed `pwsh` and `git` are immediately available.

## 7. Setup relaunches itself in PowerShell 7

If the user starts from Windows PowerShell 5.1, the bootstrap does not continue the Git workflow there. Instead, it relaunches `setup.ps1` in PowerShell 7 and resumes from there.

## 8. The real workspace clone is prepared

After reading the local bootstrap configuration, setup:

1. creates the configured workspace folder under `%USERPROFILE%`
2. resolves the repository URL from the selected endpoint type
3. clones the dotfiles repository into that workspace if it is not already present

This means the temporary bootstrap folder is not treated as the long-lived working copy.

## 9. The configured branch is enforced

Inside the real workspace clone, setup ensures the configured branch is active and up to date:

1. `git fetch origin <branch>`
2. `git checkout <branch>`
3. `git pull --ff-only origin <branch>`

If the install starts from `develop`, the real workspace clone is explicitly moved to `develop`.

## 10. Local config is copied into the real clone

When bootstrap begins from a temporary archive or another checkout, the local gitignored JSON files created during configuration are copied into the real workspace clone so the selected settings continue to apply there.

## 11. Setup validates configuration dependencies

Before running modules, setup validates dependencies declared in `setup-modules.json`. If a selected settings group requires a package group that is not selected in `INSTALL_PACKAGES`, setup stops with an error instead of proceeding with an invalid plan.

## 12. Setup builds the execution plan dynamically

The install plan is not hardcoded. `setup.ps1` builds it from local configuration files:

- `dotfiles-bootstrap-variables.json`
- `setup-modules.json`
- `windows-features.json`
- `windows-capabilities.json`
- `winget-packages.json`

The plan is assembled from four areas:

- feature modules selected by `INSTALL_FEATURES`
- capability modules selected by `INSTALL_CAPABILITIES`
- package modules selected by `INSTALL_PACKAGES`
- settings modules selected by `INSTALL_SETTINGS`

Using the current example defaults on `develop`, the resulting module order is:

1. `Configure-WindowsFeatures.ps1`
2. `Configure-WindowsCapabilities.ps1`
3. `Install-WingetPackages.ps1`
4. `Configure-WSL2.ps1`
5. `Set-EnvironmentVariables.ps1`
6. `Set-UserHomeAlias.ps1`
7. `Install-NerdFont.ps1`
8. `Install-WindowsTerminalSettings.ps1`
9. `Apply-GitConfig.ps1`
10. `Install-LocalPowerShellProfiles.ps1`
11. `Install-OmpConfig.ps1`

## 13. Modules run one by one

Each module runs in its own PowerShell process. DISM feature and capability modules use the in-box Windows PowerShell 5.1 host; other modules use PowerShell 7.

- Modules marked `requiresAdmin` are relaunched elevated when needed.
- Non-admin modules run without elevation.
- If a Windows feature or capability module returns reboot-required code `3010`, setup stops before packages and settings; restart Windows and rerun setup to continue.
- If any other module fails, setup stops immediately.

## 14. What each module does for the user

### `Configure-WindowsFeatures.ps1`

Enables the selected Windows optional features. The shared WSL 2 configuration enables `VirtualMachinePlatform`; Hyper-V remains an independently selectable feature group. When Windows reports that a restart is required, the module returns code `3010` so setup does not continue into WSL, Ubuntu, or Docker installation before the reboot.

### `Configure-WindowsCapabilities.ps1`

Installs explicitly selected Windows capability groups. The default `rsat-active-directory` group installs Server Manager before the dependent Active Directory Domain Services and Lightweight Directory Services tools. Already installed capabilities are skipped; unavailable capabilities and unsupported states fail the module. If an installation requires a restart, the module returns code `3010` immediately and defers the remaining capabilities until setup is re-run after Windows restarts.

### `Install-WingetPackages.ps1`

Installs the selected `winget` package groups, including packages that declare explicit `user` or `machine` scope.

### `Configure-WSL2.ps1`

Runs only when the `wsl` package group is selected. It sets WSL 2 as the default for future distro registrations and idempotently applies WSL 2 to an existing `Ubuntu` registration. When the Ubuntu package has not yet completed its first launch, the WSL 2 default governs that later registration.

### `Set-EnvironmentVariables.ps1`

Applies environment variables from the local environment configuration file.

### `Set-UserHomeAlias.ps1`

On machines where the profile directory contains non-ASCII characters (common on Entra ID joined devices, where the folder is created from the account displayName), creates an ASCII-only junction at `C:\Users\<upn-prefix>` pointing at the real profile directory and sets the user-scope `HOME` variable to the alias. The UPN is obtained from the in-box `whoami.exe /upn` when available, then from a valid UPN-shaped Windows identity, with a validated `USERNAME` leaf as the final fallback. Unsafe or non-ASCII alias leaves are rejected. Setup performs a read-only preflight before UAC: it prompts only for the first junction creation under `C:\Users`, runs without elevation when the correct junction exists but user-scope `HOME` needs an update, and skips the module when both are correct or the profile path is already ASCII-only. The elevated child receives explicit original-user paths, revalidates them, and performs only the junction mutation; the non-elevated parent writes `HOME` for the invoking user, so alternate Administrator credentials at the UAC prompt cannot redirect user-scoped configuration. A regular path, wrong link type, or wrong junction target fails before UAC to avoid data loss. `USERPROFILE` is never modified.

### `Install-NerdFont.ps1`

Downloads and installs the CaskaydiaCove Nerd Font for the current user.

### `Install-WindowsTerminalSettings.ps1`

Generates the Windows Terminal `settings.json` directly in the Terminal package state
(`%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState`) from the template in
`dotfiles-configurations/windows-terminal-settings.json.example`. The file is generated, not linked:
Windows Terminal owns it afterwards and machine-specific edits stay local without touching versioned
files. An existing settings.json is never overwritten; delete it to re-adopt the baseline. Does not require elevation.

> **Migration note (existing machines):** If your local `dotfiles-configurations/setup-modules.json`
> still carries `"requiresAdmin": true` for `Install-WindowsTerminalSettings.ps1` from the old
> symlink-based setup, remove that property. With the property present, `setup.ps1` relaunches the
> module as Administrator even though no elevation is needed, which contradicts the no-elevation
> design. Open your local `setup-modules.json` and delete the `"requiresAdmin": true` line from
> the `Install-WindowsTerminalSettings.ps1` entry.

### `Apply-GitConfig.ps1`

Applies the configured global Git settings such as username, email, editor, and aliases.

### `Install-LocalPowerShellProfiles.ps1`

Deploys per-machine PowerShell profiles. The real profile files are copied into
`%LOCALAPPDATA%\dotfiles\powershell-profiles`, which is never OneDrive-synced, and a small
marker stub is written into the (possibly OneDrive-synced) profile directory that dot-sources
the local copy. User-authored files without the dotfiles marker are left untouched, and any
symlink left by previous setup versions is safely replaced. Does not require elevation.

### `Install-OmpConfig.ps1`

Deploys the Oh My Posh theme files into `%USERPROFILE%\.config\oh-my-posh\poshthemes`. On `develop`, this prefers hard links and falls back to regular file copies when needed.

## 15. The final machine state

After a successful run, the user ends up with:

- a real dotfiles clone in the configured workspace
- selected packages installed
- selected Windows features enabled
- global Git settings applied
- repo-managed PowerShell profiles linked into place
- repo-managed Windows Terminal baseline generated into the Terminal package state
- Oh My Posh themes deployed
- the Nerd Font installed for terminal rendering

## 16. Rerunning setup

From the persistent workspace clone, the flow is designed to be idempotent. On later runs,
`setup-scripts\setup.ps1` reuses local config, skips already-correct state, and reapplies only what
is missing or out of date. After a reboot-required exit, continue from this clone; do not start a
new Git-free bootstrap merely to resume the module plan.

## 17. Short summary

The user journey is:

1. start bootstrap
2. create local config from templates
3. install PowerShell 7 and Git if needed
4. relaunch in PowerShell 7
5. clone or update the configured branch in the workspace
6. copy local config into the real clone
7. build the setup plan from config
8. run the selected modules
9. finish with the machine pointed at repo-managed shell and terminal configuration
