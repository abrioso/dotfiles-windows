# Packages

This repository manages Windows application packages via `winget` (Windows Package Manager).

## How packages are managed

- Shared package defaults live in `dotfiles-configurations/winget-packages.json.example`
- The configuration TUI copies that template to local `dotfiles-configurations/winget-packages.json`
- The `Install-WingetPackages.ps1` module reads the local JSON and installs the groups selected by `INSTALL_PACKAGES`
- Each entry specifies the `winget` package ID
- Setting modules can declare `requiresPackageGroups` in `setup-modules.json`; the TUI adds these groups automatically and setup validates them

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
- `poweruser` — package-management and Sysinternals tooling
- `productivity` — Microsoft Office, OneDrive, Power BI and Teams
- `pwsh` — Oh My Posh
- `wsl` — WSL and Ubuntu
