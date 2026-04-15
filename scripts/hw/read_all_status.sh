#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

usage() {
  cat <<'EOF'
Read consolidated status from Freenove board and Raspberry Pi sensors.

Usage:
  read_all_status.sh [--code-dir <path>]

Output includes:
  - Config snapshot (Fan/LED/OLED/Monitor from app_config.json)
  - Hardware temperatures (cpu, case, thermal zones, nvme if available)
  - Fan state (mode, duty, motor readback, Pi PWM)
  - LED state (mode, all LED colors)
  - Basic host stats (cpu usage, memory, disk)
EOF
}

code_dir_override=""

while [[ $# -gt 0 ]]; do
  case "$1" in
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

code_dir="$(resolve_freenove_code_dir "$code_dir_override")"
cfg_file="$(resolve_freenove_config_file "$code_dir")"

python_run_with_code_dir "$code_dir" - <<PY
import glob
import json
import os
import subprocess
from pathlib import Path

from api_expansion import Expansion
from api_systemInfo import SystemInformation

cfg_path = Path("${cfg_file}")

def section(title):
    print(f"\n[{title}]")

def read_nvme_temps():
    out = []
    devs = sorted(glob.glob('/dev/nvme*n1'))
    for dev in devs:
        try:
            txt = subprocess.check_output(["nvme", "smart-log", dev], text=True, stderr=subprocess.STDOUT)
            line = next((ln.strip() for ln in txt.splitlines() if ln.strip().lower().startswith("temperature")), None)
            out.append((os.path.basename(dev), line or "temperature: unavailable"))
        except Exception as e:
            out.append((os.path.basename(dev), f"temperature error: {e}"))
    return out

def read_thermal_zones():
    rows = []
    for zone in sorted(glob.glob('/sys/class/thermal/thermal_zone*')):
        try:
            with open(os.path.join(zone, 'type'), 'r', encoding='utf-8') as f:
                ztype = f.read().strip()
            with open(os.path.join(zone, 'temp'), 'r', encoding='utf-8') as f:
                temp = float(f.read().strip()) / 1000.0
            rows.append((os.path.basename(zone), ztype, temp))
        except Exception:
            continue
    return rows

if cfg_path.exists():
    data = json.loads(cfg_path.read_text(encoding='utf-8'))
else:
    data = {}

exp = Expansion()
sysi = SystemInformation()

try:
    section("config")
    print(f"config_file={cfg_path}")
    for key in ["Monitor", "LED", "Fan", "OLED", "Service"]:
        if key in data:
            print(f"{key}={json.dumps(data[key], ensure_ascii=True)}")

    section("host")
    print(f"cpu_usage_pct={sysi.get_raspberry_pi_cpu_usage():.2f}")
    mem = sysi.get_raspberry_pi_memory_usage()
    print(f"memory_usage={mem}")
    disk = sysi.get_raspberry_pi_disk_usage()
    print(f"disk_usage={disk}")
    print(f"ip_address={sysi.get_raspberry_pi_ip_address()}")

    section("temperature")
    print(f"cpu_temp_c={sysi.get_raspberry_pi_cpu_temperature():.2f}")
    print(f"case_temp_c={float(exp.get_temp()):.2f}")
    for zone, ztype, temp in read_thermal_zones():
        print(f"{zone}_{ztype}_c={temp:.2f}")
    nvme = read_nvme_temps()
    if nvme:
        for dev, line in nvme:
            print(f"{dev}_{line.replace(':', '=').replace(' ', '_')}")
    else:
        print("nvme=none")

    section("fan_hw")
    print(f"fan_power_switch={exp.get_fan_power_switch()}")
    print(f"fan_mode={exp.get_fan_mode()} (0=off,1=manual,2=follow-case,3=follow-rpi)")
    print(f"fan_frequency={exp.get_fan_frequency()}")
    print(f"fan_duty={exp.get_fan_duty()}")
    print(f"fan_threshold={exp.get_fan_threshold()}")
    print(f"fan_temp_mode_speed={exp.get_fan_temp_mode_speed()}")
    print(f"fan_pi_following_map={exp.get_fan_pi_following()}")
    print(f"fan_motor_speed={exp.get_motor_speed()}")
    print(f"pi_fan_pwm={sysi.get_raspberry_pi_fan_duty()}")

    section("led_hw")
    led_mode = exp.get_led_mode()
    colors = exp.get_all_led_color()
    grouped = [tuple(colors[i:i+3]) for i in range(0, len(colors), 3)]
    print(f"led_mode={led_mode} (0=off,1=manual,2=follow,3=breathing,4=rainbow)")
    print(f"led_colors_raw={colors}")
    print(f"led_colors_grouped={grouped}")

    section("board")
    print(f"i2c_address=0x{exp.get_iic_addr():02X}")
    print(f"brand={exp.get_brand()}")
    print(f"version={exp.get_version()}")
finally:
    exp.end()
PY
