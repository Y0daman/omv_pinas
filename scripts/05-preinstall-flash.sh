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

echo "[1/7] Installing utility packages (nvme-cli, smartmontools, fio)..."
sudo apt-get update
sudo apt-get install -y nvme-cli smartmontools fio

echo "[2/7] Configuring journald to keep logs in RAM (reduces SD writes)..."
sudo install -d -m 0755 /etc/systemd/journald.conf.d
sudo tee /etc/systemd/journald.conf.d/60-omv-pinas.conf >/dev/null <<'EOF'
[Journal]
Storage=volatile
RuntimeMaxUse=64M
Compress=yes
EOF

echo "[3/7] Disabling unattended apt periodic writes..."
sudo tee /etc/apt/apt.conf.d/99-omv-pinas-flash >/dev/null <<'EOF'
APT::Periodic::Enable "0";
APT::Periodic::Update-Package-Lists "0";
APT::Periodic::Download-Upgradeable-Packages "0";
APT::Periodic::Unattended-Upgrade "0";
APT::Keep-Downloaded-Packages "0";
EOF

echo "[4/7] Adding tmpfs mount for /tmp (if missing)..."
if ! grep -qE '^tmpfs\s+/tmp\s+tmpfs\s+' /etc/fstab; then
  echo "tmpfs /tmp tmpfs defaults,nosuid,nodev,noatime,size=256m 0 0" | sudo tee -a /etc/fstab >/dev/null
fi

echo "[5/7] Applying safer VM writeback tuning..."
sudo tee /etc/sysctl.d/90-omv-pinas-flash.conf >/dev/null <<'EOF'
vm.swappiness=10
vm.dirty_background_ratio=5
vm.dirty_ratio=20
vm.dirty_writeback_centisecs=1500
EOF
sudo sysctl --system >/dev/null

echo "[6/7] Applying /tmp mount and restarting journald..."
sudo mount -a
sudo systemctl restart systemd-journald

echo "[7/7] Done. Flash-write reduction baseline is active."
echo "Note: volatile logs live in RAM and are cleared on reboot."
