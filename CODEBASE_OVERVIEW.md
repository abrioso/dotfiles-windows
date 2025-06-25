# Codebase Overview

This repository contains scripts and configuration files for automating the setup of a Windows development environment.

## Directory Layout

- `setup-scripts/` – Bootstrap scripts for installing prerequisites, cloning the repository and applying DSC configurations.
- `dsc-configurations/` – WinGet Desired State Configuration (DSC) YAML files that define packages and system settings.
- `dotfiles-configurations/` – JSON files storing bootstrap variables, environment variables and package lists used by the setup scripts.
- `powershell-scripts/` – Reusable PowerShell functions and utilities.
- `powershell-profiles/` – Example profile scripts that configure modules, functions and aliases at startup.
- `windows-terminal-settings/` – Sample `settings.json` for Windows Terminal.

## Usage

Run `setup.ps1` to bootstrap the installation or `install.ps1` for a Git-free setup. The setup process applies administrative and user DSC configurations and installs common tools via WinGet.

Create an `extra.ps1` file to store private commands or secrets that you do not want to commit. This file is loaded by the PowerShell profiles if present.

## Next Steps

Explore the DSC files in `dsc-configurations/` to see which packages and configurations are applied. Review the helper scripts in `powershell-scripts/` for environment management utilities. Customize the JSON files in `dotfiles-configurations/` to tailor the installation to your needs.
