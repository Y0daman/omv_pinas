#!/usr/bin/env bash
set -euo pipefail

echo "[1/6] Modellkontroll"
if [[ -f /proc/device-tree/model ]]; then
  model="$(tr -d '\0' </proc/device-tree/model)"
  echo "- Model: ${model}"
else
  echo "- Kan inte läsa /proc/device-tree/model"
fi

echo "[2/6] Kernel"
uname -a

echo "[3/6] Blockenheter"
lsblk -o NAME,SIZE,MODEL,TYPE,MOUNTPOINT

echo "[4/6] NVMe/PCIe loggar (senaste 200 rader)"
if command -v journalctl >/dev/null 2>&1; then
  journalctl -k -n 200 | grep -Ei "nvme|pcie|aer|error|fail" || true
else
  dmesg | grep -Ei "nvme|pcie|aer|error|fail" || true
fi

echo "[5/6] Temperatur"
if command -v vcgencmd >/dev/null 2>&1; then
  vcgencmd measure_temp
else
  echo "- vcgencmd saknas (ok på vissa Debian-installationer)"
fi

echo "[6/6] SMART-verktyg"
if command -v smartctl >/dev/null 2>&1; then
  sudo smartctl --scan || true
else
  echo "- smartctl saknas, installera: sudo apt-get install -y smartmontools"
fi

echo "Klart. Verifiera att förväntat antal NVMe-diskar syns och att inga återkommande PCIe/NVMe-fel finns."
