# Logs directory

Setup scripts and modules write PowerShell transcripts to this directory during normal runs from
the persistent repository clone. Generated `*.txt` logs are ignored by Git.

## Git-free bootstrap

The Git-free installer starts the main setup transcript under
`%LOCALAPPDATA%\dotfiles\logs`. After the persistent clone is available, setup moves that transcript
into the clone's `logs` directory when possible. If `LOCALAPPDATA` or the requested log path is not
available, logging falls back to `%TEMP%`; the script reports the effective path.

Elevated Windows feature and capability modules receive explicit log paths under the persistent
clone. When those modules are run directly, they also default to this repository's `logs`
directory.

Typical filenames include the script name, timestamp and, where necessary, a unique suffix:

```plaintext
logs/
├── setup.ps1-20261001-120000.txt
├── Configure-WindowsFeatures.ps1-20261001-120100-a1b2c3d4.txt
└── Install-WingetPackages.ps1-20261001-120200.txt
```

## Security and retention

Transcripts can contain usernames, email addresses, repository endpoints, filesystem paths and
other machine-specific values. Review and redact them before sharing. Retain only the evidence
needed for troubleshooting or release acceptance, then remove obsolete logs according to the
applicable retention policy.
