# GitHub credentials and authentication

This guide describes safe GitHub authentication practices for this repository.

## Environment variables

Use local environment variables (shell profile, 1Password shell plugin, direnv, or similar):

- `GITHUB_OWNER` - account or organization, for example `Y0daman`
- `GITHUB_REPO` - repository name, for example `omv_pinas`
- `GITHUB_TOKEN` - personal access token with at least `repo` scope
- `GH_TOKEN` - optional alias for `gh` (can be the same as `GITHUB_TOKEN`)

## Example

```bash
export GITHUB_OWNER="Y0daman"
export GITHUB_REPO="omv_pinas"
export GITHUB_TOKEN="<your_pat>"
export GH_TOKEN="$GITHUB_TOKEN"

gh auth status
```

## Security rules

- Never commit tokens in code, compose files, README files, or scripts.
- Keep secrets in a local `.env` file (ignored by git).
- If a token is exposed in terminal history or logs, rotate it immediately.
- Use `gh` instead of embedding tokens in remote URLs.

## Common commands

```bash
gh repo view "$GITHUB_OWNER/$GITHUB_REPO"
gh pr create --fill
gh auth status
```
