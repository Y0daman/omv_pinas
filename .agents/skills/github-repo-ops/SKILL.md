---
name: github-repo-ops
description: Manage this repository on GitHub with secure token and gh usage. Use when creating repos, pushing branches, opening pull requests, or checking auth/env configuration.
---

# GitHub Repo Ops

## Required env vars

- `GITHUB_OWNER`
- `GITHUB_REPO`
- `GITHUB_TOKEN`
- `GH_TOKEN` (optional; can mirror `GITHUB_TOKEN`)

## Procedure

1. Run `scripts/90-github-env-check.sh`.
2. Use `gh` for repo/PR operations.
3. Keep remote URL clean (no embedded token).
4. If token is exposed in history/logs, rotate immediately.

## Validation

- `gh auth status` succeeds.
- `gh repo view "$GITHUB_OWNER/$GITHUB_REPO"` succeeds.
- No secrets tracked in git files.

## References

- `references/github-auth.md`
