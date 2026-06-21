# Packages

This repository manages Windows application packages via `winget` (Windows Package Manager).

## How packages are managed

- Shared package defaults live in `dotfiles-configurations/winget-packages.json.example`
- The configuration TUI copies that template to local `dotfiles-configurations/winget-packages.json`
- The `Install-WingetPackages.ps1` module reads the local JSON and installs the groups selected by `INSTALL_PACKAGES`
- Each entry specifies the `winget` package ID

## Adding a new package

1. Find the package ID: `winget search <name>`
2. Add it to `dotfiles-configurations/winget-packages.json.example`
3. Run `./setup-scripts/configure.ps1` again, or copy the new group/package into your local `winget-packages.json` if you already have one
4. Document its purpose below

## Package categories

### Development
- Git, Visual Studio Code, Windows Terminal, Docker Desktop, Node.js

### Productivity
- PowerToys, 7-Zip, Notepad++

### System
- Oh My Posh (terminal prompt), Nerd Fonts

### Virtualization
- Hyper-V, WSL2, Docker
