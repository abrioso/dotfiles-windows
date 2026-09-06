# dotfiles-windows (WIP)

Dotfiles for Windows, inspired by several other dotfiles repositories. This setup uses a modular, idempotent PowerShell script-based approach to configure a new machine.

The supported target is Windows 11 Pro or Enterprise. The tracked non-interactive defaults enable
Hyper-V, Windows Sandbox, WSL and RSAT capabilities; use the configuration TUI to deselect groups
that are unavailable or unwanted on a particular machine.

## Installation

> **Note:** To make this work, you need to set your PowerShell execution policy to allow scripts to run. You can do this for your user account by running the following command in PowerShell:
> `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force`

### Using Git and the Bootstrap Script

Clone the repository to your local machine (e.g., into `~\workspace\dotfiles-windows`). Once cloned, you can run the main setup script.

From PowerShell:

```pwsh
git clone https://github.com/abrioso/dotfiles-windows.git; cd dotfiles-windows; .\setup-scripts\configure.ps1; .\setup-scripts\setup.ps1
```

### Git-free Install

To install these dotfiles from PowerShell without installing Git first:

```pwsh
iex ((New-Object Net.WebClient).DownloadString('https://raw.githubusercontent.com/abrioso/dotfiles-windows/main/setup-scripts/install.ps1'))
```

Windows PowerShell 5.1 is supported as the entry point. The bootstrap installs or reuses per-user PowerShell 7 and Git prerequisites, refreshes the process path, and then continues automatically in PowerShell 7 before running Git commands.

Use the Git-free command for the initial bootstrap. After the persistent workspace clone has been
created, continue post-reboot and later idempotency runs from that clone with
`setup-scripts\setup.ps1`. A fresh Git-free archive regenerates local JSON from its templates and
is not the continuation path for preserving an existing machine's local choices.

For forks or custom archive sources, see [Configuration](docs/CONFIGURATION.md#git-free-install-parameters).

Use `-NonInteractive` with the parameterized installer when all `.json.example` defaults should be accepted without opening the configuration prompts.

## How It Works

This repository uses a main setup script (`setup.ps1`) to orchestrate a series of modular PowerShell scripts located in the `setup-modules` directory. The configuration is data-driven, with package lists, environment variables, Git settings, and repository endpoint settings defined in local JSON files in the `dotfiles-configurations` directory. Local `*.json` configuration files are intentionally gitignored; tracked defaults live in `*.json.example` templates.

The persistent `setup.ps1` process is designed to be **idempotent**, meaning you can run it multiple
times on the same machine. It will only install or change things that are not already in the desired
state. Repeated Git-free bootstrap invocation is a separate transport/configuration scenario and
must not be treated as equivalent to rerunning the persistent setup.

The setup reloads persistent bootstrap choices after configuration synchronization.
`tests/EffectiveBootstrap.Tests.ps1` covers preservation of saved opt-outs.

### Core Components

#### `setup-scripts`

This folder contains the main scripts that kick off the installation and setup process.

-   `install.ps1`: For Git-free installation. It downloads an archive to a temporary folder, resolves the extracted root, and then calls `setup.ps1`.
-   `update.ps1`: Safely fast-forwards the current dotfiles branch and optionally replaces selected local JSON files from the latest `*.json.example` templates. Existing local files are backed up first; it never runs setup modules or applies configuration. When the Windows Terminal template is refreshed, shows a diff against the live `settings.json` and can move it to the backup directory so the next setup regenerates it (`-RegenerateTerminalSettings` for unattended runs).
-   `setup.ps1`: The main bootstrap and orchestrator script. It initializes local configuration when missing, clones/updates the configured repository branch, syncs gitignored local config into the real clone, and then runs the selected modules from `setup-modules` in the order defined by the setup module catalog.
-   `setup-functions.ps1`: Contains helper functions used by the other scripts, including repository endpoint resolution and local config initialization.

#### `setup-modules`

This folder contains the modular scripts that perform the actual configuration tasks. The `setup.ps1` script calls these in sequence.

-   `Configure-WindowsFeatures.ps1`: Enables selected Windows features such as `VirtualMachinePlatform` for WSL 2 and the independently selectable Hyper-V group. If Windows requires a reboot, setup stops with code `3010`; restart and rerun before package installation continues.
-   `Configure-WindowsCapabilities.ps1`: Installs selected Windows capabilities such as the RSAT Active Directory tools. It skips capabilities already installed and also stops setup with code `3010` when Windows requires a reboot.
-   `Install-WingetPackages.ps1`: Reads local `winget-packages.json` and installs the selected package groups using the `winget` command-line tool, including optional per-package `user` or `machine` scope and `installerType` (e.g. `wix`) declarations.
-   `Configure-WSL2.ps1`: Runs after Winget when the `wsl` group is selected, sets WSL 2 as the default, and applies WSL 2 to an existing Ubuntu registration.
-   `Set-EnvironmentVariables.ps1`: Reads local `env-variables.json` and configures environment variables. Validates entries first and elevates only pending Machine changes; the child skips User entries and propagates failures. `tests/EnvironmentElevation.Tests.ps1` covers these contracts.
-   `Set-UserHomeAlias.ps1`: Creates an ASCII-only junction alias for the user profile directory (for Entra ID displayName paths with accents) and points the user-scope `HOME` variable at it. It prefers the signed-in UPN reported by the in-box `whoami.exe /upn`, with validated identity/`USERNAME` fallbacks. Setup requests UAC only when the junction must first be created under `C:\Users`; an ASCII-only profile, a fully satisfied rerun, or a rerun that only needs a user-scope `HOME` update does not prompt. The elevated child receives the original profile and alias paths explicitly and performs only the junction mutation; the non-elevated parent updates `HOME` for the invoking user, even when UAC uses different Administrator credentials.
-   `Install-LocalPowerShellProfiles.ps1`: Copies repo profiles to `%LOCALAPPDATA%\dotfiles\powershell-profiles` (never OneDrive-synced) and writes a marker stub into the profile directory that dot-sources the local copy, so profiles stay per-machine even when Documents is OneDrive-synced.
-   `Apply-GitConfig.ps1`: Reads local `git-variables.json` and applies the settings to your global Git config. Read/write failures stop setup; `tests/GitConfigFailure.Tests.ps1` covers malformed configuration and held locks.

#### `dotfiles-configurations`

This folder contains tracked `*.json.example` templates and local gitignored `*.json` files. Run `setup-scripts\configure.ps1` to create and edit local configuration interactively. See [Configuration](docs/CONFIGURATION.md) for the full file model and endpoint options.

-   `winget-packages.json.example`: Defines available `winget` package groups. The TUI copies it to local `winget-packages.json`.
-   `windows-features.json.example`: Defines available Windows optional feature groups. The TUI copies it to local `windows-features.json`.
-   `windows-capabilities.json.example`: Defines available Windows capability groups. The TUI copies it to local `windows-capabilities.json`.
-   `setup-modules.json.example`: Defines the ordered module catalog for feature, capability, package, and settings setup. The TUI copies it to local `setup-modules.json`.
-   `env-variables.json.example`: Template for custom environment variables.
-   `git-variables.json.example`: Template for global Git configuration settings, such as name, email, and aliases.
-   `dotfiles-bootstrap-variables.json.example`: Template for bootstrap variables, install groups, and repository endpoint type (`github-https`, `github-ssh`, or `custom`).

### PowerShell Profile

The setup deploys per-machine PowerShell profiles: the real profile files live in `%LOCALAPPDATA%\dotfiles\powershell-profiles` (never OneDrive-synced), and a small marker stub in the profile directory dot-sources them. This keeps your profile configuration tracked in this repository while staying personal to each machine, even when Documents is synchronised by OneDrive. The profile is composed of several files located in the `powershell-profiles` directory.

Profile stubs resolve `LOCALAPPDATA` at load time, so the same synced stub works across
machines. `tests/PortableProfile.Tests.ps1` verifies this with different local paths.

### Private files and Secrets

For any private settings, such as API tokens or Git credentials that you don't want to commit to the repository, create an `extra.ps1` file within the `powershell-profiles` directory and source it explicitly from your profile (for example from a machine-local copy under `%LOCALAPPDATA%\dotfiles\powershell-profiles`). Files in that directory are copied to the local store by `Install-LocalPowerShellProfiles.ps1`, so anything you keep there stays per-machine. The `extra.ps1` name is included in `.gitignore` so it won't be tracked by Git.

Example `extra.ps1`:

```powershell
# Set Git credentials securely
git config --global user.name "Your Name"
git config --global user.email "your.email@example.com"
```

Nerd Font setup records installed file hashes and verifies registration before skipping.
Legacy installations without this record are refreshed once; partial installations are repaired.
`tests/NerdFontRepair.Tests.ps1` covers missing/corrupt files and missing registration.

## Customization

### Forking

If you fork this repository, pass your account/repository to `install.ps1` instead of editing the script:

```pwsh
iex "& { $(irm 'https://raw.githubusercontent.com/YourGitHubAccount/YourDotfilesRepoName/main/setup-scripts/install.ps1') } -Account YourGitHubAccount -Repo YourDotfilesRepoName -Branch main"
```

For non-GitHub archive endpoints, use `-EndpointType custom-archive -ArchiveUrl <zip-url>`.

### Configuring your Setup

To customize the software, environment, endpoint type, and settings, run:

```pwsh
.\setup-scripts\configure.ps1
```

The TUI creates local gitignored JSON files from `*.json.example` templates when needed. `setup.ps1` also launches it automatically when required config files are missing. To add a new application to the shared defaults, edit `dotfiles-configurations\winget-packages.json.example`; to customize only your machine, edit the local `winget-packages.json`.

## Validation

Pull requests and pushes to `develop` or `main` run Pester, PSScriptAnalyzer, PowerShell syntax parsing, JSON parsing, and whitespace checks on Windows through GitHub Actions.

Before promoting `develop` to `main`, run the clean-install, post-reboot, idempotency, migration,
and rollback checks in [Release testing](docs/RELEASE_TESTING.md). Copy the reusable
[release evidence template](docs/RELEASE_EVIDENCE_TEMPLATE.md) outside the repository and fill it
against the exact release commit under test. Releases follow the `vYYYY.MM.N` Calendar Versioning
and Git Flow process documented in [Gitflow Policy](docs/GITFLOW.md).

## Feedback

Suggestions and improvements are [welcome and encouraged](https://github.com/abrioso/dotfiles-windows/issues)!

## Thanks to…

- @[Anthony Cangialosi](https://github.com/acangialosi)
- @[Jay Harris](https://github.com/jayharris)
