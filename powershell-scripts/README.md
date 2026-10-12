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

`functions.ps1` and `aliases.ps1` remain available; existing tests load the function helpers from
this directory. `Set-GitflowBranchProtection.ps1` remains the administrative entry point documented
in [GitFlow](../docs/GITFLOW.md). `Add-CurrentUserToHyperVAdmins.ps1`, `Start-OllamaAndWebUI.ps1` and
the two `13.docker.ollama.user*.ps1` scripts remain standalone manual tools, outside setup.
Their behavior is unchanged and is not certified by this migration: review them before use,
particularly the Docker stop script, which removes volumes. This PR does not consolidate shell
profile contents or redesign standalone container/admin tooling.
