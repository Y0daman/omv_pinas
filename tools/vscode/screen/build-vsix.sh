#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if ! command -v npm >/dev/null 2>&1; then
  echo "npm is required but not found." >&2
  exit 1
fi

echo "Installing build dependencies..."
npm install

echo "Cleaning macOS metadata files..."
find . -name '._*' -type f -delete
find . -name '.DS_Store' -type f -delete

echo "Building VSIX package..."
COPYFILE_DISABLE=1 npm run build:vsix

echo "Done. VSIX file is in: $SCRIPT_DIR"
ls -1 *.vsix
