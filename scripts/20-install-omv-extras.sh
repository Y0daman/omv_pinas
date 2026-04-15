#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -eq 0 ]]; then
  echo "Do not run as root."
  exit 1
fi

echo "Installing OMV-Extras..."
curl -fsSL https://github.com/OpenMediaVault-Plugin-Developers/packages/raw/master/install | sudo bash

echo "Installing writecache plugin if available..."
sudo apt-get update
if sudo apt-cache show openmediavault-writecache >/dev/null 2>&1; then
  sudo apt-get install -y openmediavault-writecache
  if command -v omv-salt >/dev/null 2>&1; then
    sudo omv-salt deploy run writecache || true
  fi
else
  echo "openmediavault-writecache not found in current repositories."
fi

echo "OMV-Extras installed."
echo "In OMV GUI: System -> Plugins, install what you need (for example compose)."
