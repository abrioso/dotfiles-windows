# Packages

This repository manages Windows application packages via `winget` (Windows Package Manager).

## How packages are managed

- Shared package defaults live in `dotfiles-configurations/winget-packages.json.example`
- The configuration TUI copies that template to local `dotfiles-configurations/winget-packages.json`
- The `Install-WingetPackages.ps1` module reads the local JSON and installs the groups selected by `INSTALL_PACKAGES`
- Shared defaults use object entries with an `id` plus applicable `scope` and `installerType` constraints; string entries remain supported for local configuration compatibility
- Setting modules can declare `requiresPackageGroups` in `setup-modules.json`; the TUI adds these groups automatically and setup validates them

## Package ordering and dependencies

Package arrays and package groups are ordered lists, not sets. `Install-WingetPackages.ps1` processes the package groups and their entries in declaration order, so prerequisites must appear before their dependents. Do not alphabetize groups or packages when doing so would change a required installation sequence.

The `wsl` group intentionally installs `Microsoft.WSL` before `Canonical.Ubuntu`, and the complete `wsl` group is declared before `docker` so that the WSL 2 runtime is installed before Docker Desktop. Ubuntu is not required for Docker Desktop itself, but installing it first makes subsequent WSL integration deterministic. After Winget completes, `Configure-WSL2.ps1` sets WSL 2 as the default and applies version 2 to an existing Ubuntu registration. Add a matching dependency-order contract to `tests/BootstrapReliability.Tests.ps1` when another package requires a specific predecessor.

Example with an explicit per-user scope:

```json
{
  "id": "Git.Git",
  "scope": "user"
}
```

Example selecting a WiX installer while deliberately omitting scope:

```json
{
  "id": "Microsoft.WSL",
  "installerType": "wix"
}
```

## Scope policy

Scopes must match an applicable installer in the upstream Winget manifest. A missing upstream
`Scope` is not evidence for either `user` or `machine`: forcing either value can make Winget reject
every installer with `0x8A150010` (`No applicable installer`). In that case the local entry omits
scope and may use `installerType` to select a deterministic upstream installer.

The shared defaults request `machine` scope for Docker Desktop, gsudo, Azure CLI, Edge, Office,
Power BI Desktop, Firefox, Tailscale, Google Drive, 7-Zip, Delinea Connection Manager and the
Yubico tools. These packages either publish only machine installers or
intentionally require machine-wide integration.

Packages that publish explicit user installers remain `user` scoped. Some MSIX, AppX and portable installers omit `Scope` in the upstream manifest; their existing `user` selection is retained where the installer format supports per-user deployment. When a package offers both a machine installer and a scope-neutral portable or MSIX alternative, changing its scope can change which installer type Winget selects.

`Microsoft.Azd` and `Microsoft.WSL` deliberately omit scope because their current upstream WiX
installers do not declare one. Both select `installerType: wix`; WSL's WiX installer requests the
required UAC elevation itself while the package module continues running as the current user.

`Microsoft.AppInstaller` is intentionally not part of the package pool: Winget is already a prerequisite for running the package module, so installing App Installer through Winget itself would be circular.

## Installed-state verification

`setup-scripts/winget-functions.ps1` provides the same state probe for package apply and
`setup-scripts/verify.ps1 -CheckPackages`. Queries use exact IDs, the `winget` source,
and `--scope user|machine` when declared. Display labels are not parsed; successful
queries must also expose the exact package ID. No version policy is imposed.

Some WinGet versions deny non-admin `--scope machine` queries because they enumerate
all-user MSIX registrations. On `E_ACCESSDENIED` only, the probe compares unscoped and
`user` inventories: an ID in the former but absent from the latter establishes machine
ARP/font presence. Absence from both establishes absence in those inventories. Overlapping
IDs or failed fallback queries remain `Unknown`; other-user-only MSIX registrations are
not assessed by this fallback. It does not request UAC. An elevated diagnostic can use
the direct machine query when overlap needs clarification. This follows the upstream
[installed-source inventory boundaries](https://github.com/microsoft/winget-cli/blob/master/src/AppInstallerRepositoryCore/Microsoft/PredefinedInstalledSourceFactory.cpp)
and addresses [the non-admin machine-query issue](https://github.com/microsoft/winget-cli/issues/3052).

Only WinGet's `APPINSTALLER_CLI_ERROR_NO_APPLICATIONS_FOUND` (`0x8A150014`, signed
`-1978335212`) establishes absence. Source/network/argument errors, a timed-out diagnostic
query, missing executable or missing ID evidence produce an inconclusive result.
Apply records a failure and performs no install for an inconclusive query. Diagnostics
return `Unknown`, never a false missing/success result.

If a scoped query reports absence, an unscoped query distinguishes a missing package
from an existing installation that does not match the requested scope. The latter is
`Drift` in diagnostics and blocks apply for that package. Review the existing installation
and migrate it explicitly if needed; setup does not uninstall or duplicate applications.

After a successful installer exit, apply repeats the presence/scope query. Missing,
mismatched or inconclusive post-install state is a failure; setup does not treat the exit
code alone as proof that installation completed. If registration needs a reboot or more
time to appear, complete that step and rerun setup. Install errors and verification failures
are collected across packages, then the module exits unsuccessfully.

`installerType` constrains the new installer passed to WinGet. It does **not** certify the
format of an existing installation: `winget list` has no installed-type filter, and
`winget show` describes available manifest installers rather than proving installed state.
An existing matching ID/scope is reused with a warning when an installer type was requested;
the diagnostic remains `Unknown`. A new install with that constraint is also reported as
type-inconclusive even after presence/scope verification. This avoids inferring WiX from MSI
registry flags or reinstalling packages merely to manufacture evidence.

Apply may accept source agreements as part of the authorized installation. Diagnostics
remain opt-in and do not accept agreements, elevate, install, remove or upgrade packages;
WinGet may still access its sources and write its own cache/logs.

References: [WinGet list options](https://learn.microsoft.com/en-us/windows/package-manager/winget/list),
[WinGet show metadata](https://learn.microsoft.com/en-us/windows/package-manager/winget/show),
and [official return codes](https://github.com/microsoft/winget-cli/blob/master/doc/windows/package-manager/winget/returnCodes.md).
`tests/WingetState.Tests.ps1` covers state classification and the production apply loop;
`tests/SetupDiagnostic.Tests.ps1` covers report integration and privacy.

## Adding a new package

1. Find the package ID: `winget search <name>`
2. Add it to `dotfiles-configurations/winget-packages.json.example`
3. Run `./setup-scripts/configure.ps1` again, or copy the new group/package into your local `winget-packages.json` if you already have one
4. Document its purpose below

## Package categories

- `base` — 7-Zip, Git, PowerShell, Visual Studio Code and Windows Terminal
- `browsers` — Chrome, Edge and Firefox
- `dev` — Git, GitHub CLI, PowerShell, Visual Studio Code, Python 3.13 and Yaak (API client)
- `azure` — Azure Developer CLI (`azd`), Azure CLI, PowerShell and Visual Studio Code
- `docker` — Docker Desktop
- `delinea` — optional Delinea Connection Manager for remote connection management
- `google-drive` — optional Google Drive for desktop, providing machine-wide Drive integration
- `multimedia` — OBS Studio and VLC
- `poweruser` — package-management and power-user tooling
- `powerbi` — optional Power BI Desktop, installed with machine scope
- `productivity` — Microsoft Office, OneDrive and Teams
- `pwsh` — PowerShell, Windows Terminal and Oh My Posh (all with `user` scope)
- `tailscale` — optional Tailscale client and system service for mesh VPN connectivity
- `wsl` — WSL and Ubuntu
- `yubico` — optional Yubico Authenticator, YubiKey Manager and YubiKey Manager CLI

The `azure`, `powerbi`, `tailscale`, `delinea`, `yubico` and `google-drive` groups are available
in the configuration TUI but are not selected in the shared bootstrap defaults. Select them in
`INSTALL_PACKAGES` when required.

`Microsoft.365Copilot` is intentionally excluded from the shared package catalog because clean
release acceptance exposed an unreliable Winget installation path. Reconsider it only after the
upstream package installs successfully in both clean-install and idempotency scenarios.

Existing local configurations are preserved during updates. Rename `PowerBI` to `powerbi` in
local `winget-packages.json` and `INSTALL_PACKAGES`; remove `azure` and `powerbi` from the local
`INSTALL_PACKAGES` array to adopt the new default selection.

The former `development` group is split into `dev` and `azure`. Only `dev` is selected in the
shared bootstrap defaults; add `azure` explicitly when Azure tooling is required. The `developer`
settings group requires `dev` for Git configuration. Packages shared by selected groups are
deduplicated. For existing local configurations, refresh `winget-packages.json` and
`setup-modules.json` from their templates, preserving any customizations, and replace
`development` in `dotfiles-bootstrap-variables.json`'s `INSTALL_PACKAGES` with `dev` and,
optionally, `azure`.

## Selected package scopes and elevation

The package module itself runs as the current user. Winget or an application installer may request
UAC only when the selected installer requires machine-wide changes. Package installs explicitly
select the `winget` community source because the shared catalog contains Winget package IDs rather
than Microsoft Store product IDs; this also avoids first-run `msstore` source initialization
affecting bootstrap installs.

| Package | Requested scope | Expected elevation |
| --- | --- | --- |
| `7zip.7zip` | `machine` | Yes when installation is required; upstream installers declare machine scope. |
| `Delinea.DelineaConnectionManager` | `machine` | Yes when installation is required; upstream WiX installer declares machine scope. |
| `Yaak.app` | `user` | Normally no; upstream NSIS installer declares user scope. |
| `Yubico.Authenticator` | `machine` | Yes when installation is required; upstream WiX installer declares machine scope. |
| `Yubico.YubikeyManager` | `machine` | Yes when installation is required; upstream NSIS installers declare machine scope. |
| `Yubico.YubiKeyManagerCLI` | `machine` | Yes when installation is required; upstream WiX installer declares machine scope. |
| `Docker.DockerDesktop` | `machine` | Yes when installation is required. |
| `gerardog.gsudo` | `machine` | Yes when installation is required; gsudo installs system integration. |
| `Git.Git` | `machine` | Yes when installation is required; bootstrap and package groups both request machine scope. |
| `Google.GoogleDrive` | `machine` | Yes when installation is required; Drive for desktop installs machine-wide integration. |
| `Microsoft.Azd` | omitted; WiX pinned | No UAC was required in the clean-machine validation; its upstream WiX installer has no declared scope. |
| `Microsoft.AzureCLI` | `machine` | Yes when installation is required. |
| `Microsoft.Edge` | `machine` | Yes when installation is required; Edge is normally already provisioned by Windows. |
| `Microsoft.Office` | `machine` | Yes when installation is required. |
| `Microsoft.PowerBI` | `machine` | Yes when installation is required; the upstream installer is machine-only. |
| `Microsoft.Teams` | `machine` | Yes when installation is required; the new Teams installer supports machine-wide deployment. |
| `Mozilla.Firefox` | `machine` | Yes when installation is required; the upstream installer is machine-scoped. |
| `Microsoft.PowerShell` | `user` | Normally no; Winget can select the per-user MSIX package. |
| `Microsoft.VisualStudioCode` | `user` | Normally no; selects the user installer. |
| `Microsoft.WindowsTerminal` | `user` | Normally no; installs as an MSIX package for the user. |
| `Microsoft.WSL` | omitted; WiX pinned | Yes when installation is required; the WiX installer presents UAC. |
| `Tailscale.Tailscale` | `machine` | Yes when installation is required; Tailscale installs its system service and network integration. |

Git and PowerShell are also bootstrap prerequisites. If missing, setup installs Git with `machine`
scope and PowerShell with `user` scope before processing package groups, matching their catalog
entries. The prerequisite check reuses an existing command on PATH; the package module then
verifies the configured scope and reports any mismatch.

Scopes for the additions above were checked on 2026-09-06 against the Winget installer manifests:
[7-Zip 26.02](https://github.com/microsoft/winget-pkgs/blob/master/manifests/7/7zip/7zip/26.02/7zip.7zip.installer.yaml),
[Delinea 2.9.0.33](https://github.com/microsoft/winget-pkgs/blob/master/manifests/d/Delinea/DelineaConnectionManager/2.9.0.33/Delinea.DelineaConnectionManager.installer.yaml),
[Yaak 2026.7.1](https://github.com/microsoft/winget-pkgs/blob/master/manifests/y/Yaak/app/2026.7.1/Yaak.app.installer.yaml),
[Yubico Authenticator 7.4.1](https://github.com/microsoft/winget-pkgs/blob/master/manifests/y/Yubico/Authenticator/7.4.1/Yubico.Authenticator.installer.yaml),
[YubiKey Manager 1.2.6](https://github.com/microsoft/winget-pkgs/blob/master/manifests/y/Yubico/YubikeyManager/1.2.6/Yubico.YubikeyManager.installer.yaml), and
[YubiKey Manager CLI 5.9.2](https://github.com/microsoft/winget-pkgs/blob/master/manifests/y/Yubico/YubiKeyManagerCLI/5.9.2/Yubico.YubiKeyManagerCLI.installer.yaml).
