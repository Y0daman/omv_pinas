# GitHub auth reference

- GitHub CLI manual: https://cli.github.com/manual/
- PAT creation and management: https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/creating-a-personal-access-token

Recommended minimum environment variables:

- `GITHUB_OWNER`
- `GITHUB_REPO`
- `GITHUB_TOKEN`
- `GH_TOKEN` (optional alias)

Security baseline:

- Never commit secrets.
- Keep credentials in local env management.
- Rotate immediately after accidental exposure.
