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

echo "Installing Cockpit packages..."
sudo apt-get update
sudo apt-get install -y cockpit cockpit-pcp cockpit-storaged

echo "Enabling Cockpit service..."
sudo systemctl enable --now cockpit.socket

echo "Configuring Webmin repository and key..."
sudo install -d -m 0755 /usr/share/keyrings
if [[ ! -f /usr/share/keyrings/webmin-archive-keyring.gpg ]]; then
  curl -fsSL https://download.webmin.com/jcameron-key.asc | gpg --dearmor | sudo tee /usr/share/keyrings/webmin-archive-keyring.gpg >/dev/null
fi

if [[ ! -f /etc/apt/sources.list.d/webmin.list ]]; then
  printf '%s\n' "deb [signed-by=/usr/share/keyrings/webmin-archive-keyring.gpg] https://download.webmin.com/download/repository sarge contrib" | sudo tee /etc/apt/sources.list.d/webmin.list >/dev/null
fi

echo "Installing Webmin..."
sudo apt-get update
sudo apt-get install -y webmin

echo
echo "Install complete."
echo "- Cockpit: https://<PI-IP>:9090"
echo "- Webmin:  https://<PI-IP>:10000"
echo "Note: OMV uses port 80 by default and does not conflict with these ports."
