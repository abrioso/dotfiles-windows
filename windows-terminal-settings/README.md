# Windows Terminal settings

This directory is intentionally kept minimal in version control.

What is tracked:
- `README.md` (this file)

What is not tracked:
- `settings.json` — per-machine Windows Terminal configuration.

The tracked baseline is stored as a JSON template in `dotfiles-configurations/windows-terminal-settings.json.example`.
The setup module `Install-WindowsTerminalSettings.ps1` derives the local `settings.json` from that template and
creates a symbolic link from the Windows Terminal LocalState directory to the local file.

Do not commit local changes to `settings.json`. Add machine-specific profiles (WSL, Ubuntu, custom paths, GUIDs)
only to the local copy in this directory or in the Windows Terminal UI.
