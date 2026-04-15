#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

usage() {
  cat <<'EOF'
Read temperatures from available sensors.

Usage:
  read_temp.sh [--sensor all|cpu|case|nvme|thermal] [--code-dir <path>]

Examples:
  ./scripts/hw/read_temp.sh
  ./scripts/hw/read_temp.sh --sensor cpu
  ./scripts/hw/read_temp.sh --sensor nvme
EOF
}

sensor="all"
code_dir_override=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sensor)
      sensor="${2:-all}"
      shift 2
      ;;
    --code-dir)
      code_dir_override="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ ! "$sensor" =~ ^(all|cpu|case|nvme|thermal)$ ]]; then
  echo "--sensor must be one of: all,cpu,case,nvme,thermal" >&2
  exit 1
fi

code_dir="$(resolve_freenove_code_dir "$code_dir_override")"

python_run_with_code_dir "$code_dir" - <<PY
import glob
import os
import subprocess
from api_expansion import Expansion
from api_systemInfo import SystemInformation

sensor = "${sensor}"
sysinfo = SystemInformation()
exp = Expansion()

def print_cpu_temp():
    print(f"cpu_temp_c={sysinfo.get_raspberry_pi_cpu_temperature():.2f}")

def print_case_temp():
    print(f"case_temp_c={float(exp.get_temp()):.2f}")

def print_nvme_temps():
    devs = sorted(glob.glob('/dev/nvme*n1'))
    if not devs:
        print("nvme_temps=none")
        return
    for dev in devs:
        try:
            out = subprocess.check_output(["nvme", "smart-log", dev], text=True, stderr=subprocess.STDOUT)
            temp_line = next((ln for ln in out.splitlines() if ln.strip().lower().startswith("temperature")), None)
            if temp_line:
                print(f"{os.path.basename(dev)}_{temp_line.strip().replace(':', '=').replace(' ', '_')}")
            else:
                print(f"{os.path.basename(dev)}_temperature=unavailable")
        except Exception as e:
            print(f"{os.path.basename(dev)}_temperature_error={e}")

def print_thermal_zones():
    zones = sorted(glob.glob('/sys/class/thermal/thermal_zone*'))
    if not zones:
        print("thermal_zones=none")
        return
    for z in zones:
        try:
            with open(os.path.join(z, 'type'), 'r', encoding='utf-8') as f:
                ztype = f.read().strip()
            with open(os.path.join(z, 'temp'), 'r', encoding='utf-8') as f:
                raw = f.read().strip()
            value = float(raw) / 1000.0
            print(f"{os.path.basename(z)}_{ztype}_c={value:.2f}")
        except Exception:
            continue

try:
    if sensor in ("all", "cpu"):
        print_cpu_temp()
    if sensor in ("all", "case"):
        print_case_temp()
    if sensor in ("all", "nvme"):
        print_nvme_temps()
    if sensor in ("all", "thermal"):
        print_thermal_zones()
finally:
    exp.end()
PY
