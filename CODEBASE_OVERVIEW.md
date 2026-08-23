# Codebase Overview

This repository contains scripts and configuration files for automating the setup of a Windows development environment.

## Directory Layout

- `setup-scripts/` – Bootstrap scripts for installing prerequisites, cloning the repository and applying setup modules.
- `dotfiles-configurations/` – JSON templates for bootstrap variables, package groups, Windows feature groups, environment variables, Git config and setup module selection.
- `powershell-scripts/` – Reusable PowerShell functions and utilities.
- `powershell-profiles/` – Example profile scripts that configure modules, functions and aliases at startup.
- `windows-terminal-settings/` – Documentation for Windows Terminal settings; `settings.json` is generated directly into the Terminal package LocalState from the template in `dotfiles-configurations/windows-terminal-settings.json.example`.

## Usage

Run `setup.ps1` to bootstrap the installation or `install.ps1` for a Git-free setup. Configuration is template-driven: tracked `dotfiles-configurations/*.json.example` files are copied to local gitignored `*.json` files by `setup-scripts/configure.ps1` when needed. The setup process applies administrative and user configuration modules and installs selected tools via WinGet.

Create an `extra.ps1` file to store private commands or secrets that you do not want to commit. This file is loaded by the PowerShell profiles if present.

## Next Steps

Review the helper scripts in `powershell-scripts/` for environment management utilities. Customize the local JSON files in `dotfiles-configurations/` to tailor the installation to your needs, or update the tracked `*.json.example` templates to change shared defaults.
