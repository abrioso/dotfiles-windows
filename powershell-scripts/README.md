# Legacy setup migration and standalone utilities

Setup is owned by `setup-scripts/setup.ps1`, the current JSON catalogs and `setup-modules`.
Ten historical provisioning scripts retain their filenames as **non-mutating migration guards**.
Executing one now throws a terminating error with the replacement command. They do not install,
download, change registry/environment values, create links or forward to setup automatically.
An unattended caller must migrate; it can no longer rely on the historical provisioning behavior.
The previous implementations remain available in Git history.

## Migration

Run `setup-scripts/configure.ps1` to review local configuration, then inspect
`setup-scripts/setup.ps1 -Plan` before explicitly applying `setup-scripts/setup.ps1`.
Package and setting groups are ordered selections; a modern group can contain more components
than its historical script. No legacy script changes those selections on your behalf.

| Retired path in this directory | Current owner or migration |
| --- | --- |
| `06.base.configuration.user.ps1` | Setup prerequisites and the selected `base` package group; workspace comes from bootstrap configuration. |
| `07.pwsh.terminal.configuration.user.ps1` | Selected `base`/`pwsh` setup: packages, Terminal, Nerd Font, themes and `Install-LocalPowerShellProfiles.ps1`. Existing unmarked profiles are preserved; no `PowerShell-Custom` symlink is created. |
| `09.developer.configuration.user.ps1` | Review the `dev` package group; it is broader than the old VS Code-only script. |
| `2.hyperv.wsl.configuration.admin.ps1` | Select `hyperv`/`wsl` feature groups and `wsl` packages. Hyper-V group membership is separate administration, not a setup module. |
| `3.docker.packages.admin.ps1` | Select the desired `wsl`/`hyperv` features and `wsl`/`docker` packages. Respect setup's reboot boundary before continuing installation. |
| `4.developer.configuration.admin.ps1` | Developer Mode has no current setup equivalent; manage it explicitly in Windows Settings. |
| `Apply-Env-Variables.ps1` | `setup-modules/Set-EnvironmentVariables.ps1` reads the current `EnvironmentVariables` array with `Name`, `Value`, `Scope`. It does not use the obsolete top-level key/value schema. |
| `Configure-OMP.ps1` | `Install-OmpConfig.ps1` owns themes; `Install-NerdFont.ps1` owns the current font. Terminal-Icons remains an optional manually installed PowerShell module. |
| `Install-NerdFont.ps1` | `setup-modules/Install-NerdFont.ps1` installs per-user CaskaydiaCove. This is not the old system-wide FiraCode deployment; no old fonts are removed by the migration guard. |
| `Install-Winget-Packages.ps1` | `setup-modules/Install-WingetPackages.ps1` reads grouped package catalogs and bootstrap selections, not the obsolete `Packages` property. |

Direct module invocation still has that module's prerequisites, configuration and privilege
requirements. Prefer the orchestrator for feature/package ordering and reboot handling.

## Diagnostic migration

`tests/Verify-PowerShellProfiles.ps1` is a compatibility wrapper for `setup-scripts/verify.ps1`
and requires PowerShell 7.2 or later. It checks **all selected components**, validates all existing
local configuration first and returns canonical exit codes: `0` passed/skipped only, `1` drift,
`2` inconclusive. It no longer assumes an organization-specific OneDrive path, previews profile
contents or writes `Verify-PowerShellProfiles.results.json`. The JSON schema is the new diagnostic
schema; existing consumers of the old file/report must migrate. Text mode emits a deprecation
warning; `-Format Json` emits only the canonical report. `-CheckPackages` is forwarded explicitly.

```powershell
.\setup-scripts\verify.ps1
.\setup-scripts\verify.ps1 -Format Json
```

See [Installed-state diagnostic](../docs/CONFIGURATION.md#installed-state-diagnostic) for coverage
and limitations. Old generated reports already present on a machine are not deleted automatically.

## Retained utilities

`functions.ps1`, `aliases.ps1`, `Set-GitflowBranchProtection.ps1` and
`Add-CurrentUserToHyperVAdmins.ps1` remain standalone utilities outside setup.

## Ollama Compose lifecycle

The Compose helpers require an explicit `-ComposePath`; they do not select a stack from the
current working directory. The optional `-ProjectName` must match the existing Compose project
on every invocation. Omitting it preserves Docker Compose's directory-based naming behavior.
The start command creates a missing file with a managed marker, preserves existing content,
validates Compose and checks `up --wait` before reporting success. It requires a Compose version
supporting `--wait`. New files bind ports to localhost and make Watchtower opt-in through the
`automatic-updates` profile. Existing files are never silently updated.

```powershell
.\powershell-scripts\13.docker.ollama.user.ps1 -ComposePath C:\stacks\ollama\docker-compose.yml
.\powershell-scripts\13.docker.ollama.user.stop.ps1 -ComposePath C:\stacks\ollama\docker-compose.yml
.\powershell-scripts\13.docker.ollama.user.stop.ps1 -ComposePath C:\stacks\ollama\docker-compose.yml -Action Down
```

The default `Stop` preserves containers and volumes. `Down` removes containers/networks but
preserves volumes. `Purge` deletes persistent data and requests high-impact confirmation;
`-WhatIf` previews it. Only an intentional `-Confirm:$false` suppresses this confirmation.
All Docker errors produce a failing exit code and prevent a success message.

For a file produced by the old generator, first review its services, ports and volume definitions,
then add `# dotfiles-managed ollama compose v1` as its first line. Keep the original directory,
Compose filename, project name and volume definitions to retain existing data. The marker is an
ownership guard against accidentally selecting another Compose file, not an authenticity check.
Do not generate a replacement stack in another directory and assume it will use the same volumes.

`Start-OllamaAndWebUI.ps1` now stops with migration guidance. Its direct `docker run` volumes
(`ollama` and `open-webui`) differ from the Compose generator's volumes. Back up and explicitly
map those existing volumes (for example with external named volumes) before migrating. No script
removes old containers or migrates volumes automatically.

`docker-compose-functions.ps1` centralizes file selection and native exit-code handling;
`tests/DockerLifecycle.Tests.ps1` verifies the lifecycle with a fake Docker command. Runtime
GPU/network checks remain part of Windows acceptance. Application stack development should
be consolidated in akb-docker-stack separately from Windows host provisioning.
