# Configuration

This repository separates tracked defaults from machine-specific configuration.

## File model

Tracked templates live in `dotfiles-configurations/` with a `.json.example` suffix:

| Template | Local file created by the TUI | Purpose |
| --- | --- | --- |
| `dotfiles-bootstrap-variables.json.example` | `dotfiles-bootstrap-variables.json` | Bootstrap settings, repository endpoint type, install groups, and workspace path. |
| `winget-packages.json.example` | `winget-packages.json` | Available `winget` package groups and package IDs. |
| `windows-features.json.example` | `windows-features.json` | Available Windows optional feature groups and feature names. |
| `setup-modules.json.example` | `setup-modules.json` | Ordered setup module plan for features, packages, and settings. |
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

```json
{
  "INSTALL_PACKAGES": [
    "base",
    "development",
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

The `-Branch` value is used for both the downloaded archive and the repository checkout, so a bootstrap started from `develop` or another branch does not switch back to the template's default branch.
The branch override is persisted to the local bootstrap JSON and therefore remains active on later setup runs.

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

1. Missing Git and PowerShell prerequisites are installed for the current user.
2. A bootstrap started from Windows PowerShell 5.1 relaunches itself in PowerShell 7 before running Git commands.
3. Missing local config files are created from the `.json.example` templates.
4. The repository is cloned, if needed, using the selected endpoint type.
5. The configured branch is fetched, checked out, and fast-forward pulled.
6. Local gitignored configuration generated during git-free bootstrap is copied into the real workspace clone after branch checkout.
7. Setup validates package-group dependencies declared by selected settings.
8. Setup builds an ordered module plan from `setup-modules.json` and the selected `INSTALL_FEATURES`, `INSTALL_PACKAGES`, and `INSTALL_SETTINGS` values.
9. Setup modules consume the local `*.json` files and setup stops if a configured module is missing or fails.

The `base` setting installs the CaskaydiaCove Nerd Font before applying Windows Terminal settings because the tracked terminal configuration references that font. Oh My Posh themes use non-elevated hard links when source and target are on the same volume, with a regular copy fallback across volumes.
