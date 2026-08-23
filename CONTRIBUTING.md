# Contributing

## Branching Strategy

This project uses **gitflow**. See [docs/GITFLOW.md](docs/GITFLOW.md) for the full policy, enforcement details, and workflow examples.

## How to Contribute

1. **Fork** or create a feature branch from `develop`:
   ```bash
   git checkout develop && git pull
   git checkout -b feature/my-change
   ```

2. **Make your changes** following the code standards below.

3. **Commit** using [Conventional Commits](https://www.conventionalcommits.org/):
   - `feat:` — new feature
   - `fix:` — bug fix
   - `docs:` — documentation only
   - `chore:` — maintenance, deps
   - `refactor:` — code restructure without behavior change

4. **Push and open a PR** targeting `develop`:
   ```bash
   git push -u origin feature/my-change
   gh pr create --base develop
   ```

5. **Wait for review** before merging.

## Code Standards

### PowerShell Scripts
- Follow PowerShell best practices and naming conventions (Verb-Noun)
- Must pass PSScriptAnalyzer cleanly
- Must be idempotent (safe to re-run)
- Use functions for logical grouping
- Add comment-based help for user-facing scripts

### Documentation
- Update `README.md` when adding features
- Document new packages in `docs/PACKAGES.md` and add them to `dotfiles-configurations/winget-packages.json.example`
- Treat package groups and their arrays as ordered lists: prerequisites must precede dependents; alphabetize only when it preserves dependency order

### Configuration
- Shared configuration defaults live in `dotfiles-configurations/*.json.example`
- Local machine-specific `dotfiles-configurations/*.json` files are gitignored and must not be committed
- PowerShell profiles go in `powershell-profiles/`
- Setup modules are in `setup-modules/` (one task per module)

## Release Process

1. Complete [the release acceptance matrix](docs/RELEASE_TESTING.md) on `develop`.
2. Create `release/vYYYY.MM.N` from an up-to-date `origin/develop`.
3. Apply only release stabilization changes and open a PR into `main`.
4. Merge the production PR with a merge commit.
5. If the release branch has release-only commits, merge the same branch into `develop` through
   a second PR; do not merge `main` wholesale back into `develop`.
6. Tag the verified `main` merge commit and publish the matching GitHub Release.
7. Delete the release branch only after production and integration reconciliation are complete.

Versions use Calendar Versioning: `vYYYY.MM.N`, for example `v2026.08.0`. `N` normally starts at
`0` and increments for additional releases in the same month; it may instead be mapped explicitly
to the day of the month for a date-oriented release identifier.
