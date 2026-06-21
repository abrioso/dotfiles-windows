# Contributing

## Branching Strategy

This project uses **gitflow**:

| Branch | Purpose | Merges into |
|--------|---------|-------------|
| main | Stable releases | — |
| develop | Next release integration | main (via release PR) |
| feature/* | New functionality | develop |
| fix/* | Non-urgent fixes | develop |
| hotfix/* | Critical fixes | main + develop |
| release/* | Release prep | main |

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
- Keep lists sorted alphabetically

### Configuration
- Application configs live in `dotfiles-configurations/` as JSON
- PowerShell profiles go in `powershell-profiles/`
- Setup modules are in `setup-modules/` (one task per module)

## Release Process

1. Create `release/vX.Y.Z` from `develop`
2. Bump version references, update CHANGELOG
3. PR into `main`, tag after merge
4. Merge `main` back into `develop`
