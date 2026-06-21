# dotfiles-windows (WIP)

Dotfiles for Windows, inspired by several other dotfiles repositories. This setup uses a modular, idempotent PowerShell script-based approach to configure a new machine.

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
iex ((new-object net.webclient).DownloadString('https://raw.githubusercontent.com/abrioso/dotfiles-windows/main/setup-scripts/install.ps1'))
```

## How It Works

This repository uses a main setup script (`setup.ps1`) to orchestrate a series of modular PowerShell scripts located in the `setup-modules` directory. The configuration is data-driven, with package lists, environment variables, Git settings, and repository endpoint settings defined in local JSON files in the `dotfiles-configurations` directory. Local `*.json` configuration files are intentionally gitignored; tracked defaults live in `*.json.example` templates.

The entire process is designed to be **idempotent**, meaning you can run the setup script multiple times on the same machine. It will only install or change things that are not already in the desired state.

### Core Components

#### `setup-scripts`

This folder contains the main scripts that kick off the installation and setup process.

-   `install.ps1`: For Git-free installation. It downloads the repository to a temporary folder and then calls `setup.ps1`.
-   `setup.ps1`: The main bootstrap and orchestrator script. This script performs initial setup tasks (like creating symlinks and cloning the repo if necessary) and then runs the modules from the `setup-modules` directory in the correct order.
-   `setup-functions.ps1`: Contains helper functions used by the other scripts.

#### `setup-modules`

This folder contains the modular scripts that perform the actual configuration tasks. The `setup.ps1` script calls these in sequence.

-   `Configure-WindowsFeatures.ps1`: Enables necessary Windows features like WSL and Hyper-V. Requires administrator privileges.
-   `Install-WingetPackages.ps1`: Reads local `winget-packages.json` and installs the selected package groups using the `winget` command-line tool.
-   `Set-EnvironmentVariables.ps1`: Reads local `env-variables.json` and configures environment variables.
-   `Apply-GitConfig.ps1`: Reads local `git-variables.json` and applies the settings to your global Git config.

#### `dotfiles-configurations`

This folder contains tracked `*.json.example` templates and local gitignored `*.json` files. Run `setup-scripts\configure.ps1` to create and edit local configuration interactively.

-   `winget-packages.json.example`: Defines available `winget` package groups. The TUI copies it to local `winget-packages.json`.
-   `env-variables.json.example`: Template for custom environment variables.
-   `git-variables.json.example`: Template for global Git configuration settings, such as name, email, and aliases.
-   `dotfiles-bootstrap-variables.json.example`: Template for bootstrap variables, install groups, and repository endpoint type (`github-https`, `github-ssh`, or `custom`).

### PowerShell Profile

The setup creates a symbolic link to manage your PowerShell profile, allowing you to keep your profile configuration in this repository. The profile is composed of several files located in the `powershell-profiles` directory.

### Private files and Secrets

For any private settings, such as API tokens or Git credentials that you don't want to commit to the repository, you can create a `extra.ps1` file within the `powershell-profiles` directory. If this file exists, it will be automatically sourced when your PowerShell profile loads. This file is included in `.gitignore` so it won't be tracked by Git.

Example `extra.ps1`:

```powershell
# Set Git credentials securely
git config --global user.name "Your Name"
git config --global user.email "your.email@example.com"
```

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

The TUI creates local gitignored JSON files from `*.json.example` templates when needed. To add a new application to the shared defaults, edit `dotfiles-configurations\winget-packages.json.example`; to customize only your machine, edit the local `winget-packages.json`.

## Feedback

Suggestions and improvements are [welcome and encouraged](https://github.com/abrioso/dotfiles-windows/issues)!

## Thanks to…

- @[Anthony Cangialosi](https://github.com/acangialosi)
- @[Jay Harris](https://github.com/jayharris)
