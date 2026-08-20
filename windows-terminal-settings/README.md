# Windows Terminal settings

This directory contains documentation for Windows Terminal settings.

The setup module `Install-WindowsTerminalSettings.ps1` derives the local `settings.json`
from the tracked baseline template in `dotfiles-configurations/windows-terminal-settings.json.example`
and places the local file in `dotfiles-configurations/windows-terminal-settings.json`, where it
is ignored by the existing `.gitignore` rule for machine-local JSON files.

The module then creates a symbolic link from the Windows Terminal LocalState directory to that
local file so the terminal loads the configuration from its conventional location.

Do not commit local changes to `settings.json`. Add machine-specific profiles (WSL, Ubuntu, custom
paths, GUIDs) only to the local copy in `dotfiles-configurations/` or through the Windows Terminal UI.
