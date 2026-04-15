#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../hw/common.sh
source "$SCRIPT_DIR/../hw/common.sh"

usage() {
  cat <<'EOF'
Control Freenove case fan behavior.

Usage:
  set_fan_percent.sh manual <percent> [--persist] [--code-dir <path>]
  set_fan_percent.sh follow-case [--low-temp C] [--high-temp C] [--schmitt C] \
                     [--low-speed P] [--mid-speed P] [--high-speed P] [--persist] [--code-dir <path>]
  set_fan_percent.sh follow-rpi [--min-speed P] [--max-speed P] [--persist] [--code-dir <path>]
  set_fan_percent.sh target-temp <C> [--sensor cpu|case] [--min-speed P] [--max-speed P] \
                     [--gain P_PER_C] [--interval S] [--duration S] [--persist] [--code-dir <path>]
  set_fan_percent.sh off [--persist] [--code-dir <path>]
  set_fan_percent.sh get [--code-dir <path>]
  set_fan_percent.sh read [--code-dir <path>]
  set_fan_percent.sh status [--code-dir <path>]   # alias for read

Backward-compatible shortcut:
  set_fan_percent.sh <percent>   # same as: manual <percent>

Mode details:
  manual      Fixed duty on all fan channels (FAN1&2, FAN3&4, FAN5 if present)
  follow-case Controller auto mode based on case temperature sensor
  follow-rpi  Controller follows Raspberry Pi PWM duty
  target-temp Active control loop to maintain desired temperature

Ranges:
  percent/speed: 0..100
  low-temp/high-temp: 0..100 (Celsius)
  schmitt: 0..20
EOF
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

cmd="$1"
shift || true

# Backward compatibility: numeric first argument means manual percent.
if [[ "$cmd" =~ ^[0-9]+$ ]]; then
  set -- "$cmd" "$@"
  cmd="manual"
fi

persist=0
code_dir_override=""

require_int_in_range() {
  local name="$1"
  local value="$2"
  local min="$3"
  local max="$4"
  if [[ ! "$value" =~ ^[0-9]+$ ]] || (( value < min || value > max )); then
    echo "$name must be an integer in [$min, $max]. Got: $value" >&2
    exit 1
  fi
}

percent_to_duty() {
  local p="$1"
  echo $(( (p * 255 + 50) / 100 ))
}

read_common_flags() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --persist)
        persist=1
        shift
        ;;
      --code-dir)
        code_dir_override="${2:-}"
        shift 2
        ;;
      *)
        break
        ;;
    esac
  done
  printf '%s\n' "$@"
}

case "$cmd" in
  -h|--help)
    usage
    exit 0
    ;;

  get)
    set -- $(read_common_flags "$@")
    code_dir="$(resolve_freenove_code_dir "$code_dir_override")"
    ensure_freenove_config_exists "$code_dir"
    cfg_file="$(resolve_freenove_config_file "$code_dir")"

    python3 - <<PY
import json
from pathlib import Path

cfg = Path("${cfg_file}")
if not cfg.exists():
    print(f"Missing config file: {cfg}")
    raise SystemExit(1)

data = json.loads(cfg.read_text(encoding="utf-8"))
fan = data.get("Fan", {})
print(f"Config file: {cfg}")
print("Fan configured values (software config):")
for key in [
    "mode", "mode1_fan_group1", "mode1_fan_group2", "mode1_fan_group3",
    "mode2_low_temp_threshold", "mode2_high_temp_threshold", "mode2_temp_schmitt",
    "mode2_low_speed", "mode2_middle_speed", "mode2_high_speed",
    "mode3_min_speed_mapping", "mode3_max_speed_mapping",
    "task_name", "is_run_on_startup"
]:
    if key in fan:
        print(f"- {key}: {fan[key]}")
PY
    ;;

  manual)
    if [[ $# -lt 1 ]]; then
      echo "manual mode requires <percent>" >&2
      exit 1
    fi
    percent="$1"
    shift
    require_int_in_range "percent" "$percent" 0 100
    set -- $(read_common_flags "$@")

    code_dir="$(resolve_freenove_code_dir "$code_dir_override")"
    duty="$(percent_to_duty "$percent")"

    python_run_with_code_dir "$code_dir" - <<PY
from api_expansion import Expansion

percent = ${percent}
duty = ${duty}
persist = ${persist}

exp = Expansion()
try:
    exp.set_fan_power_switch(1)
    exp.set_fan_mode(1)
    exp.set_fan_frequency(50000)
    exp.set_fan_duty(duty, duty, duty)
    if persist:
        exp.set_save_flash(1)

    print(f"Fan mode: manual")
    print(f"Set duty: {percent}% ({duty}/255) on all channels")
    print(f"Readback duty: {exp.get_fan_duty()}")
    print(f"Motor speed readback: {exp.get_motor_speed()}")
finally:
    exp.end()
PY
    ;;

  follow-case)
    low_temp=30
    high_temp=50
    schmitt=3
    low_speed_p=30
    mid_speed_p=50
    high_speed_p=70

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --low-temp) low_temp="${2:-}"; shift 2 ;;
        --high-temp) high_temp="${2:-}"; shift 2 ;;
        --schmitt) schmitt="${2:-}"; shift 2 ;;
        --low-speed) low_speed_p="${2:-}"; shift 2 ;;
        --mid-speed) mid_speed_p="${2:-}"; shift 2 ;;
        --high-speed) high_speed_p="${2:-}"; shift 2 ;;
        --persist|--code-dir)
          set -- $(read_common_flags "$@")
          break
          ;;
        *)
          echo "Unknown argument for follow-case: $1" >&2
          exit 1
          ;;
      esac
    done

    require_int_in_range "low-temp" "$low_temp" 0 100
    require_int_in_range "high-temp" "$high_temp" 0 100
    require_int_in_range "schmitt" "$schmitt" 0 20
    require_int_in_range "low-speed" "$low_speed_p" 0 100
    require_int_in_range "mid-speed" "$mid_speed_p" 0 100
    require_int_in_range "high-speed" "$high_speed_p" 0 100

    if (( low_temp >= high_temp )); then
      echo "low-temp must be lower than high-temp." >&2
      exit 1
    fi

    low_speed="$(percent_to_duty "$low_speed_p")"
    mid_speed="$(percent_to_duty "$mid_speed_p")"
    high_speed="$(percent_to_duty "$high_speed_p")"

    code_dir="$(resolve_freenove_code_dir "$code_dir_override")"

    python_run_with_code_dir "$code_dir" - <<PY
from api_expansion import Expansion

low_temp = ${low_temp}
high_temp = ${high_temp}
schmitt = ${schmitt}
low_speed = ${low_speed}
mid_speed = ${mid_speed}
high_speed = ${high_speed}
persist = ${persist}

exp = Expansion()
try:
    exp.set_fan_power_switch(1)
    exp.set_fan_mode(2)
    exp.set_fan_threshold(low_temp, high_temp, schmitt)
    exp.set_fan_temp_mode_speed(low_speed, mid_speed, high_speed)
    if persist:
        exp.set_save_flash(1)

    print("Fan mode: follow-case (temperature)")
    print(f"Thresholds: low={low_temp}C high={high_temp}C schmitt={schmitt}")
    print(f"Duty steps: low={low_speed}/255 mid={mid_speed}/255 high={high_speed}/255")
    print(f"Current case temp: {exp.get_temp()}C")
    print(f"Readback duty: {exp.get_fan_duty()}")
finally:
    exp.end()
PY
    ;;

  follow-rpi)
    min_speed_p=0
    max_speed_p=100

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --min-speed) min_speed_p="${2:-}"; shift 2 ;;
        --max-speed) max_speed_p="${2:-}"; shift 2 ;;
        --persist|--code-dir)
          set -- $(read_common_flags "$@")
          break
          ;;
        *)
          echo "Unknown argument for follow-rpi: $1" >&2
          exit 1
          ;;
      esac
    done

    require_int_in_range "min-speed" "$min_speed_p" 0 100
    require_int_in_range "max-speed" "$max_speed_p" 0 100
    if (( min_speed_p > max_speed_p )); then
      echo "min-speed cannot be greater than max-speed." >&2
      exit 1
    fi

    min_speed="$(percent_to_duty "$min_speed_p")"
    max_speed="$(percent_to_duty "$max_speed_p")"

    code_dir="$(resolve_freenove_code_dir "$code_dir_override")"

    python_run_with_code_dir "$code_dir" - <<PY
from api_expansion import Expansion

min_speed = ${min_speed}
max_speed = ${max_speed}
persist = ${persist}

exp = Expansion()
try:
    exp.set_fan_power_switch(1)
    exp.set_fan_mode(3)
    exp.set_fan_pi_following(min_speed, max_speed)
    if persist:
        exp.set_save_flash(1)

    print("Fan mode: follow-rpi (Pi PWM mapping)")
    print(f"Mapping duty: min={min_speed}/255 max={max_speed}/255")
    print(f"Readback map: {exp.get_fan_pi_following()}")
    print(f"Readback duty: {exp.get_fan_duty()}")
finally:
    exp.end()
PY
    ;;

  target-temp)
    if [[ $# -lt 1 ]]; then
      echo "target-temp mode requires target temperature in C" >&2
      exit 1
    fi
    target_temp="$1"
    shift

    sensor="cpu"
    min_speed_p=20
    max_speed_p=100
    gain=4
    interval="2.0"
    duration="0"

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --sensor) sensor="${2:-}"; shift 2 ;;
        --min-speed) min_speed_p="${2:-}"; shift 2 ;;
        --max-speed) max_speed_p="${2:-}"; shift 2 ;;
        --gain) gain="${2:-}"; shift 2 ;;
        --interval) interval="${2:-}"; shift 2 ;;
        --duration) duration="${2:-}"; shift 2 ;;
        --persist|--code-dir)
          set -- $(read_common_flags "$@")
          break
          ;;
        *)
          echo "Unknown argument for target-temp: $1" >&2
          exit 1
          ;;
      esac
    done

    if [[ "$sensor" != "cpu" && "$sensor" != "case" ]]; then
      echo "--sensor must be cpu or case" >&2
      exit 1
    fi
    require_int_in_range "min-speed" "$min_speed_p" 0 100
    require_int_in_range "max-speed" "$max_speed_p" 0 100
    if (( min_speed_p > max_speed_p )); then
      echo "min-speed cannot be greater than max-speed." >&2
      exit 1
    fi

    code_dir="$(resolve_freenove_code_dir "$code_dir_override")"

    python_run_with_code_dir "$code_dir" - <<PY
import time
from api_expansion import Expansion
from api_systemInfo import SystemInformation

target_temp = float("${target_temp}")
sensor = "${sensor}"
min_speed_p = float(${min_speed_p})
max_speed_p = float(${max_speed_p})
gain = float(${gain})
interval = float(${interval})
duration = float(${duration})
persist = ${persist}

if max_speed_p < min_speed_p:
    raise SystemExit("max-speed must be >= min-speed")

def clamp(v, lo, hi):
    return max(lo, min(hi, v))

def pct_to_duty(pct):
    return int(round(clamp(pct, 0.0, 100.0) * 255.0 / 100.0))

exp = Expansion()
sysinfo = SystemInformation()

try:
    exp.set_fan_power_switch(1)
    exp.set_fan_mode(1)
    exp.set_fan_frequency(50000)
    if persist:
      exp.set_save_flash(1)

    start = time.time()
    while True:
        if sensor == "cpu":
            temp = float(sysinfo.get_raspberry_pi_cpu_temperature())
        else:
            temp = float(exp.get_temp())

        error = temp - target_temp
        speed_pct = clamp(min_speed_p + gain * error, min_speed_p, max_speed_p)
        duty = pct_to_duty(speed_pct)
        exp.set_fan_duty(duty, duty, duty)

        print(f"sensor={sensor} temp={temp:.2f}C target={target_temp:.2f}C speed={speed_pct:.1f}% duty={duty}/255")

        if duration > 0 and (time.time() - start) >= duration:
            break
        time.sleep(interval)
finally:
    exp.end()
PY
    ;;

  off)
    set -- $(read_common_flags "$@")
    code_dir="$(resolve_freenove_code_dir "$code_dir_override")"

    python_run_with_code_dir "$code_dir" - <<PY
from api_expansion import Expansion

persist = ${persist}

exp = Expansion()
try:
    exp.set_fan_mode(0)
    exp.set_fan_duty(0, 0, 0)
    exp.set_fan_power_switch(0)
    if persist:
        exp.set_save_flash(1)
    print("Fan mode: off")
finally:
    exp.end()
PY
    ;;

  read|status)
    set -- $(read_common_flags "$@")
    code_dir="$(resolve_freenove_code_dir "$code_dir_override")"

    python_run_with_code_dir "$code_dir" - <<'PY'
import glob
from api_expansion import Expansion
from api_systemInfo import SystemInformation

def read_pi_fan_rpm():
    candidates = sorted(glob.glob('/sys/devices/platform/cooling_fan/hwmon/hwmon*/fan1_input'))
    for path in candidates:
        try:
            with open(path, 'r', encoding='utf-8') as f:
                return int(f.read().strip())
        except Exception:
            continue
    return None

exp = Expansion()
sysi = SystemInformation()
try:
    print(f"Fan power switch: {exp.get_fan_power_switch()}")
    print(f"Fan mode: {exp.get_fan_mode()} (0=off,1=manual,2=follow-case,3=follow-rpi)")
    print(f"Fan frequency: {exp.get_fan_frequency()}")
    print(f"Fan duty (channels): {exp.get_fan_duty()}")
    print(f"Fan thresholds [low,high,schmitt]: {exp.get_fan_threshold()}")
    print(f"Fan temp mode speeds [low,mid,high]: {exp.get_fan_temp_mode_speed()}")
    print(f"Fan RPi mapping [min,max]: {exp.get_fan_pi_following()}")
    print(f"Case temperature: {exp.get_temp()}C")
    print(f"Motor speed readback: {exp.get_motor_speed()}")
    pi_pwm = sysi.get_raspberry_pi_fan_duty()
    print(f"Pi fan PWM: {pi_pwm} (0..255)")
    pi_rpm = read_pi_fan_rpm()
    if pi_rpm is None:
        print("Pi fan RPM: unavailable")
    else:
        print(f"Pi fan RPM: {pi_rpm}")
finally:
    exp.end()
PY
    ;;

  *)
    echo "Unknown command: $cmd" >&2
    usage
    exit 1
    ;;
esac
