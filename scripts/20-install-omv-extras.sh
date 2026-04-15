#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -eq 0 ]]; then
  echo "Kör inte scriptet som root."
  exit 1
fi

echo "Installerar OMV-Extras..."
curl -fsSL https://github.com/OpenMediaVault-Plugin-Developers/packages/raw/master/install | sudo bash

echo "OMV-Extras installerat."
echo "I OMV GUI: System -> Plugins, installera det du behöver (t.ex. compose)."
