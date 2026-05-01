# AI Agent Instructions

This repository follows **gitflow** branching and requires **Pull Requests** for all changes.

## Branching Model

- `main` — production-ready, tagged releases only
- `develop` — integration branch for next release
- `feature/<name>` — new features (branch from `develop`)
- `hotfix/<name>` — urgent fixes (branch from `main`, merge to both `main` and `develop`)
- `release/<version>` — release prep (branch from `develop`, merge to `main`)

## Rules for Agents

1. **Never push directly to `main` or `develop`** — always create a feature branch and open a PR.
2. **Branch naming**: `feature/short-description`, `fix/short-description`, `hotfix/short-description`
3. **Commits**: Use conventional commits (`feat:`, `fix:`, `docs:`, `chore:`, `refactor:`)
4. **One logical change per PR** — don't bundle unrelated changes.
5. **PR description**: Explain what and why. Link related issues if any.
6. **Tests/validation**: Run PSScriptAnalyzer on all .ps1 files before committing.
7. **Worktrees**: Use `git worktree` for parallel work instead of stashing or switching branches.

## Workflow Example

```bash
# Start a new feature
git checkout develop
git pull origin develop
git checkout -b feature/add-docker-config

# Work, commit
git add -A
git commit -m "feat: add docker daemon config"

# Push and create PR
git push -u origin feature/add-docker-config
gh pr create --base develop --title "feat: add docker config" --body "Adds daemon.json and compose aliases"
```

## Code Standards

- Shell scripts: `#!/bin/bash` with `set -euo pipefail`
- Pass `shellcheck` with no warnings
- All scripts must be idempotent (safe to re-run)
- Document new files in README.md
- Keep package lists sorted alphabetically

## Repository Owner

- **Name**: André Brioso
- **GitHub**: @abrioso
- **Email**: akbrioso@iseg.ulisboa.pt
