#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -eq 0 ]]; then
  echo "Do not run as root. Use a regular sudo-enabled user."
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_NAME="omv-pinas-screen-button.service"
SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}"

GPIO_PIN="${GPIO_PIN:-17}"
HOLD_SECONDS="${HOLD_SECONDS:-0.8}"
DEBOUNCE_SECONDS="${DEBOUNCE_SECONDS:-0.05}"

echo "Installing dependencies..."
sudo apt-get update
sudo apt-get install -y python3-gpiozero

echo "Creating systemd service ${SERVICE_NAME}..."
sudo tee "${SERVICE_PATH}" >/dev/null <<EOF
[Unit]
Description=OMV PiNAS Button Screen Controller
After=multi-user.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 ${SCRIPT_DIR}/button_screen_control.py --gpio-pin ${GPIO_PIN} --hold-seconds ${HOLD_SECONDS} --debounce-seconds ${DEBOUNCE_SECONDS}
WorkingDirectory=${SCRIPT_DIR}
Restart=always
RestartSec=1
User=root

[Install]
WantedBy=multi-user.target
EOF

echo "Reloading systemd and enabling service..."
sudo systemctl daemon-reload
sudo systemctl enable --now "${SERVICE_NAME}"

echo "Installed and started: ${SERVICE_NAME}"
echo "Status: sudo systemctl status ${SERVICE_NAME}"
echo "Logs:   sudo journalctl -u ${SERVICE_NAME} -f"
