#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -eq 0 ]]; then
  echo "Do not run as root. Use a regular sudo-enabled user." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_NAME="${SERVICE_NAME:-screen-dashboard.service}"
SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}"

RUN_USER="${RUN_USER:-$USER}"
SCREEN_BACKEND="${SCREEN_BACKEND:-linuxfb}"
SCREEN_ROTATION="${SCREEN_ROTATION:-}"
SCREEN_CLEAN_STALE="${SCREEN_CLEAN_STALE:-1}"
FREENOVE_CODE_DIR="${FREENOVE_CODE_DIR:-}"

if [[ -n "$SCREEN_ROTATION" && ! "$SCREEN_ROTATION" =~ ^(0|90|180|270)$ ]]; then
  echo "SCREEN_ROTATION must be one of: 0,90,180,270" >&2
  exit 1
fi

if ! id "$RUN_USER" >/dev/null 2>&1; then
  echo "RUN_USER does not exist: $RUN_USER" >&2
  exit 1
fi

launcher="$SCRIPT_DIR/screen-dashboard-launcher.sh"
if [[ ! -x "$launcher" ]]; then
  echo "Missing launcher script: $launcher" >&2
  echo "Tip: chmod +x $launcher" >&2
  exit 1
fi

echo "Installing ${SERVICE_NAME}..."
sudo tee "$SERVICE_PATH" >/dev/null <<EOF
[Unit]
Description=OMV PiNAS Freenove Screen Dashboard
After=multi-user.target network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${RUN_USER}
WorkingDirectory=${SCRIPT_DIR}
Environment=SCREEN_BACKEND=${SCREEN_BACKEND}
Environment=SCREEN_ROTATION=${SCREEN_ROTATION}
Environment=SCREEN_CLEAN_STALE=${SCREEN_CLEAN_STALE}
Environment=FREENOVE_CODE_DIR=${FREENOVE_CODE_DIR}
ExecStart=${launcher}
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

echo "Reloading systemd and enabling ${SERVICE_NAME}..."
sudo systemctl daemon-reload
sudo systemctl enable --now "$SERVICE_NAME"

echo "Installed and started: ${SERVICE_NAME}"
echo "Status: sudo systemctl status ${SERVICE_NAME}"
echo "Logs:   sudo journalctl -u ${SERVICE_NAME} -f"
