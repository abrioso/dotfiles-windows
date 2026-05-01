# Packages

This repository manages Windows application packages via `winget` (Windows Package Manager).

## How packages are managed

- Package definitions live in `dotfiles-configurations/winget-packages.json`
- The `Install-WingetPackages.ps1` module reads this JSON and installs all listed applications
- Each entry specifies the winget package ID

## Adding a new package

1. Find the package ID: `winget search <name>`
2. Add it to `dotfiles-configurations/winget-packages.json`
3. Document its purpose below

## Package categories

### Development
- Git, Visual Studio Code, Windows Terminal, Docker Desktop, Node.js

### Productivity
- PowerToys, 7-Zip, Notepad++

### System
- Oh My Posh (terminal prompt), Nerd Fonts

### Virtualization
- Hyper-V, WSL2, Docker
