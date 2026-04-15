#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -eq 0 ]]; then
  echo "Do not run as root. Use a regular sudo-enabled user."
  exit 1
fi

if ! command -v sudo >/dev/null 2>&1; then
  echo "sudo is missing. Install sudo first."
  exit 1
fi

echo "Installing packages previously installed on the target host..."

packages=(
  git
  mc
  python3-luma.oled
  python3-pip
  python3-smbus
  python3-psutil
  python3-pyqt5
)

sudo apt-get update
sudo apt-get install -y "${packages[@]}"

echo "Done. Reinstalled history-derived toolset."
