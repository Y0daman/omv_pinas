#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -eq 0 ]]; then
  echo "Do not run as root."
  exit 1
fi

echo "Installing OpenMediaVault using the official installer..."
echo "This can take a while."

wget -O - https://get.openmediavault.io | sudo bash

echo "OMV installation complete."
echo "Open: http://$(hostname -I | awk '{print $1}')/"
