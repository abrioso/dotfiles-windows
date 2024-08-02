# dotfiles-windows (WIP)

Dotfiles for Windows inspired from several other dotfiles.

## Installation

> **Note:** To make this work, you need to set your execution policy to unrestricted (or at least bypass) by running `Set-ExecutionPolicy Unrestricted` from a PowerShell running as Administrator.

### Using Git and the bootstrap script

To clone the repository, you can choose any location you prefer. I personally keep it in `~\workspace\dotfiles-windows`. Once cloned, the bootstrapper script will run the setup scripts.

From PowerShell:

```pwsh
git clone https://github.com/abrioso/dotfiles-windows.git; cd dotfiles-windows; cd setup-scripts; .\setup.ps1
```

### Git-free install

To install these dotfiles from PowerShell without Git:

```pwsh
iex ((new-object net.webclient).DownloadString('https://raw.githubusercontent.com/abrioso/dotfiles-windows/main/setup-scripts/install.ps1'))
```

## Use & Configuration

### Desired State Configuration (DSC) files

The folder "dsc-configurations" contains the DSC configuration files:

- `.\dsc-configuration\base-configurations.yaml` : Base and must-have configuration.

### PowerShell Profile

The following commands are executed every time you launch a new
PowerShell window.

- `.\components.ps1` : Load various PowerShell components and modules.
- `.\functions.ps1` : Configure custom PowerShell functions.
- `.\aliases.ps1` : Configure alias-based commands.
- `.\exports.ps1` : Configure environment variables.
- `.\extra.ps1` : Secrets and secret commands that are not tracked by the Git repository.

Also included are default configurations for Git, Mercurial, Ruby, NPM, and vim.

### Private files and Secrets

You may have scripts or commands that you want to execute when loading PowerShell that you do not want committed into your own `dotfiles` repository, such as a place to put tokens or credentials or even your Git commit email address. For such secret commands, use `.\extra.ps1`.

If `.\extra.ps1` exists, it will be sourced along with the other files.

My `.\extra.ps1` looks something like this:

```posh

# Git credentials
# Not in the repository, to prevent people from accidentally committing under my name
Set-Environment "GIT_AUTHOR_NAME" "Andre Kakoo Brioso"
Set-Environment "GIT_COMMITTER_NAME" $env:GIT_AUTHOR_NAME
git config --global user.name $env:GIT_AUTHOR_NAME
Set-Environment "GIT_AUTHOR_EMAIL" "akbrioso@iseg.ulisboa.pt"
Set-Environment "GIT_COMMITTER_EMAIL" $env:GIT_AUTHOR_EMAIL
git config --global user.email $env:GIT_AUTHOR_EMAIL
```

Extras is designed to augment the existing settings and configuration. You could also use `./extra.ps1` to override settings, functions and aliases from my dotfiles repository, but it is probably better to [fork this repository](#forking-your-own-version).

## Customization

## Forking your own version

If you decide to fork this repository for your own custom configuration, make sure to modify the `install.ps1` file to reference your own repository instead of mine.

Within `/scripts/install.ps1`, modify the Repository variables.

```pwsh
$account = "abrioso"
$repo    = "dotfiles-windows"
$branch  = "main"
```

And make sure to update the git-free installation command with the URL of your own repository.

```pwsh
iex ((new-object net.webclient).DownloadString('https://raw.githubusercontent.com/$account/$repo/$branch/setup/install.ps1'))
```

## Feedback

Suggestions/improvements are
[welcome and encouraged](https://github.com/abrioso/dotfiles-windows/issues)!

## Author

## Thanks to…

- @[Anthony Cangialosi](https://github.com/acangialosi)
- @[Jay Harris](https://github.com/jayharris)

For the inspiration and for sharing their dotfiles:

1. <https://github.com/acangialosi/dotfiles>
2. <https://github.com/jayharris/dotfiles-windows>

Other Sources:

1. <https://github.com/microsoft/devhome/tree/main/docs/sampleConfigurations/DscResources>
2. <https://nicksnettravels.builttoroam.com/winget-configuration/>
3. <https://learn.microsoft.com/en-us/windows/package-manager/configuration/>
4. <https://github.com/microsoft/winget-create/tree/main/Tools>
5. <https://github.com/microsoft/winget-cli>
6. <https://github.com/PowerShell/PSDscResources>
