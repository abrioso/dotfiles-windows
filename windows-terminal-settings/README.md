# Windows Terminal settings

This directory contains documentation for Windows Terminal settings.

The setup module `Install-WindowsTerminalSettings.ps1` copies the baseline template from
`dotfiles-configurations/windows-terminal-settings.json.example` directly into the Windows
Terminal LocalState directory as `settings.json` on first run.

The file is **generated, not linked**: Windows Terminal owns it afterwards.
Machine-specific edits (WSL profiles, Ubuntu entries, per-machine fonts) are written by
Terminal directly into that file without ever touching versioned files.

- On subsequent runs the existing `settings.json` is **never overwritten**, so local
  customizations are preserved.
- No symlink is created, so no elevation or Developer Mode is required.
- To re-adopt the baseline defaults, delete the generated `settings.json` and re-run setup,
  or copy `dotfiles-configurations/windows-terminal-settings.json.example` manually.
