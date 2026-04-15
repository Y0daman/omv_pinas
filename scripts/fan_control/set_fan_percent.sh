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
  set_fan_percent.sh off [--persist] [--code-dir <path>]
  set_fan_percent.sh status [--code-dir <path>]

Backward-compatible shortcut:
  set_fan_percent.sh <percent>   # same as: manual <percent>

Mode details:
  manual      Fixed duty on all fan channels (FAN1&2, FAN3&4, FAN5 if present)
  follow-case Controller auto mode based on case temperature sensor
  follow-rpi  Controller follows Raspberry Pi PWM duty

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

  status)
    set -- $(read_common_flags "$@")
    code_dir="$(resolve_freenove_code_dir "$code_dir_override")"

    python_run_with_code_dir "$code_dir" - <<'PY'
from api_expansion import Expansion

exp = Expansion()
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
