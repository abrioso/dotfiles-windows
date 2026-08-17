# Packages

This repository manages Windows application packages via `winget` (Windows Package Manager).

## How packages are managed

- Shared package defaults live in `dotfiles-configurations/winget-packages.json.example`
- The configuration TUI copies that template to local `dotfiles-configurations/winget-packages.json`
- The `Install-WingetPackages.ps1` module reads the local JSON and installs the groups selected by `INSTALL_PACKAGES`
- String entries specify a `winget` package ID; object entries can also declare `id` and `scope`
- Setting modules can declare `requiresPackageGroups` in `setup-modules.json`; the TUI adds these groups automatically and setup validates them

## Package ordering and dependencies

Package arrays are ordered lists, not sets. `Install-WingetPackages.ps1` processes entries in declaration order, so prerequisites must appear before their dependents. Do not alphabetize a package group when doing so would change a required installation sequence.

The `wsl` group intentionally installs `Microsoft.WSL` before `Canonical.Ubuntu`. Add a matching dependency-order contract to `tests/BootstrapReliability.Tests.ps1` when another package requires a specific predecessor.

Example with an explicit per-user scope:

```json
{
  "id": "Git.Git",
  "scope": "user"
}
```

## Adding a new package

1. Find the package ID: `winget search <name>`
2. Add it to `dotfiles-configurations/winget-packages.json.example`
3. Run `./setup-scripts/configure.ps1` again, or copy the new group/package into your local `winget-packages.json` if you already have one
4. Document its purpose below

## Package categories

- `base` — Git, PowerShell, Visual Studio Code, Windows Terminal, Edge and gsudo
- `browsers` — Chrome, Edge and Firefox
- `development` — Azure tooling, Dev Home, GitHub CLI, Python, Git, PowerShell and Visual Studio Code
- `docker` — Docker Desktop
- `multimedia` — OBS Studio and VLC
- `poweruser` — package-management and power-user tooling
- `PowerBI` — Power BI Desktop, installed with machine scope
- `productivity` — Microsoft Office, OneDrive and Teams
- `pwsh` — Oh My Posh
- `wsl` — WSL and Ubuntu

## Base package scopes and elevation

The package module itself runs as the current user. Winget or an application installer may request UAC only when the selected installer requires machine-wide changes.

| Package | Requested scope | Expected elevation |
| --- | --- | --- |
| `gerardog.gsudo` | `machine` | Yes when installation is required; gsudo installs system integration. |
| `Git.Git` | `user` | Normally no. Git also publishes a machine installer, but bootstrap deliberately selects the user installer. |
| `Microsoft.Edge` | `machine` | Yes when installation is required; Edge is normally already provisioned by Windows. |
| `Microsoft.PowerShell` | `user` | Normally no; Winget can select the per-user MSIX package. |
| `Microsoft.VisualStudioCode` | `user` | Normally no; selects the user installer. |
| `Microsoft.WindowsTerminal` | `user` | Normally no; installs as an MSIX package for the user. |

Git and PowerShell are also bootstrap prerequisites. If missing, setup installs them explicitly with `user` scope before processing package groups. An existing installation in either scope is reused.
