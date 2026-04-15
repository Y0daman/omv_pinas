#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -eq 0 ]]; then
  echo "Kör inte som root. Använd en vanlig användare med sudo."
  exit 1
fi

if ! command -v sudo >/dev/null 2>&1; then
  echo "sudo saknas. Installera sudo först."
  exit 1
fi

echo "[1/5] Kontrollerar OS-version..."
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
  echo "- Detekterat OS: ${PRETTY_NAME:-unknown}"
else
  echo "Kunde inte läsa /etc/os-release"
  exit 1
fi

echo "[2/5] Uppdaterar paketindex och system..."
sudo apt-get update
sudo apt-get -y full-upgrade

echo "[3/5] Installerar basverktyg..."
sudo apt-get install -y curl wget git ca-certificates gnupg lsb-release jq

echo "[4/5] Säkerställer korrekt hostname i /etc/hosts..."
current_host="$(hostname)"
if ! grep -q "${current_host}" /etc/hosts; then
  echo "127.0.1.1 ${current_host}" | sudo tee -a /etc/hosts >/dev/null
fi

echo "[5/5] Klar. Rekommenderar reboot innan OMV-installation."
echo "Kör: sudo reboot"
