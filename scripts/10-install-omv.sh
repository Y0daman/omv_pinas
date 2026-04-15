#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -eq 0 ]]; then
  echo "Kör inte scriptet som root."
  exit 1
fi

echo "Installerar OpenMediaVault (officiellt installscript)..."
echo "Detta kan ta en stund."

curl -fsSL https://github.com/OpenMediaVault-Plugin-Developers/installScript/raw/master/install | sudo bash

echo "OMV-installation klar."
echo "Öppna: http://$(hostname -I | awk '{print $1}')/"
