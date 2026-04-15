#!/usr/bin/env bash
set -euo pipefail

required=(GITHUB_OWNER GITHUB_REPO GITHUB_TOKEN)

missing=0
for var in "${required[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    echo "MISSING: ${var}"
    missing=1
  else
    echo "OK: ${var}"
  fi
done

if [[ -z "${GH_TOKEN:-}" && -n "${GITHUB_TOKEN:-}" ]]; then
  echo "INFO: GH_TOKEN är inte satt. Du kan sätta: export GH_TOKEN=\"$GITHUB_TOKEN\""
fi

if [[ "${missing}" -ne 0 ]]; then
  echo "En eller flera variabler saknas."
  exit 1
fi

if command -v gh >/dev/null 2>&1; then
  GH_TOKEN="${GH_TOKEN:-$GITHUB_TOKEN}" gh auth status || true
else
  echo "gh CLI saknas. Installera från: https://cli.github.com/manual/installation"
fi

echo "GitHub env-kontroll klar."
