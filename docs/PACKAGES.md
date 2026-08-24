# Packages

This repository manages Windows application packages via `winget` (Windows Package Manager).

## How packages are managed

- Shared package defaults live in `dotfiles-configurations/winget-packages.json.example`
- The configuration TUI copies that template to local `dotfiles-configurations/winget-packages.json`
- The `Install-WingetPackages.ps1` module reads the local JSON and installs the groups selected by `INSTALL_PACKAGES`
- Shared defaults use object entries with explicit `id` and `scope`; string entries remain supported for local configuration compatibility
- Setting modules can declare `requiresPackageGroups` in `setup-modules.json`; the TUI adds these groups automatically and setup validates them

## Package ordering and dependencies

Package arrays and package groups are ordered lists, not sets. `Install-WingetPackages.ps1` processes the package groups and their entries in declaration order, so prerequisites must appear before their dependents. Do not alphabetize groups or packages when doing so would change a required installation sequence.

The `wsl` group intentionally installs `Microsoft.WSL` before `Canonical.Ubuntu`, and the complete `wsl` group is declared before `docker` so that the WSL 2 runtime is installed before Docker Desktop. Ubuntu is not required for Docker Desktop itself, but installing it first makes subsequent WSL integration deterministic. After Winget completes, `Configure-WSL2.ps1` sets WSL 2 as the default and applies version 2 to an existing Ubuntu registration. Add a matching dependency-order contract to `tests/BootstrapReliability.Tests.ps1` when another package requires a specific predecessor.

Example with an explicit per-user scope:

```json
{
  "id": "Git.Git",
  "scope": "user"
}
```

## Scope policy

Scopes must match an applicable installer in the upstream Winget manifest. The shared defaults request `machine` scope for Docker Desktop, gsudo, Azure CLI, Edge, Office, Power BI Desktop and Firefox. These packages either publish only machine installers or intentionally require machine-wide integration.

Packages that publish explicit user installers remain `user` scoped. Some MSIX, AppX and portable installers omit `Scope` in the upstream manifest; their existing `user` selection is retained where the installer format supports per-user deployment. When a package offers both a machine installer and a scope-neutral portable or MSIX alternative, changing its scope can change which installer type Winget selects.

`Microsoft.AppInstaller` is intentionally not part of the package pool: Winget is already a prerequisite for running the package module, so installing App Installer through Winget itself would be circular.

## Adding a new package

1. Find the package ID: `winget search <name>`
2. Add it to `dotfiles-configurations/winget-packages.json.example`
3. Run `./setup-scripts/configure.ps1` again, or copy the new group/package into your local `winget-packages.json` if you already have one
4. Document its purpose below

## Package categories

- `base` — Git, PowerShell, Visual Studio Code and Windows Terminal
- `browsers` — Chrome, Edge and Firefox
- `development` — Azure tooling, Dev Home, GitHub CLI, Python, Git, PowerShell and Visual Studio Code
- `docker` — Docker Desktop
- `multimedia` — OBS Studio and VLC
- `poweruser` — package-management and power-user tooling
- `PowerBI` — Power BI Desktop, installed with machine scope
- `productivity` — Microsoft Office, OneDrive and Teams
- `pwsh` — Oh My Posh
- `wsl` — WSL and Ubuntu

## Selected package scopes and elevation

The package module itself runs as the current user. Winget or an application installer may request
UAC only when the selected installer requires machine-wide changes. Package installs explicitly
select the `winget` community source because the shared catalog contains Winget package IDs rather
than Microsoft Store product IDs; this also avoids first-run `msstore` source initialization
affecting bootstrap installs.

| Package | Requested scope | Expected elevation |
| --- | --- | --- |
| `Docker.DockerDesktop` | `machine` | Yes when installation is required. |
| `gerardog.gsudo` | `machine` | Yes when installation is required; gsudo installs system integration. |
| `Git.Git` | `user` | Normally no. Git also publishes a machine installer, but bootstrap deliberately selects the user installer. |
| `Microsoft.AzureCLI` | `machine` | Yes when installation is required. |
| `Microsoft.Edge` | `machine` | Yes when installation is required; Edge is normally already provisioned by Windows. |
| `Microsoft.Office` | `machine` | Yes when installation is required. |
| `Microsoft.PowerBI` | `machine` | Yes when installation is required; the upstream installer is machine-only. |
| `Microsoft.Teams` | `machine` | Yes when installation is required; the new Teams installer supports machine-wide deployment. |
| `Mozilla.Firefox` | `machine` | Yes when installation is required; the upstream installer is machine-scoped. |
| `Microsoft.PowerShell` | `user` | Normally no; Winget can select the per-user MSIX package. |
| `Microsoft.VisualStudioCode` | `user` | Normally no; selects the user installer. |
| `Microsoft.WindowsTerminal` | `user` | Normally no; installs as an MSIX package for the user. |

Git and PowerShell are also bootstrap prerequisites. If missing, setup installs them explicitly with `user` scope before processing package groups. An existing installation in either scope is reused.
