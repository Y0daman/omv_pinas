#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../hw/common.sh
source "$SCRIPT_DIR/../hw/common.sh"

usage() {
  cat <<'EOF'
Control Freenove case RGB LEDs.

Usage:
  led_control.sh <command> [options]

Commands:
  get
  read
  status
  off
  rainbow
  floating-rainbow
  preset <name>
  list-presets
  manual <R> <G> <B>
  breathing <R> <G> <B>
  follow <R> <G> <B>
  temp-follow [--sensor cpu|case] [--cold C] [--hot C] [--interval S] [--duration S]
  demo-wheel [seconds]
  demo-palette [seconds]

Options:
  --persist             Save config to controller flash
  --code-dir <path>     Path to Freenove Code directory

Notes:
  - Mode mapping from Freenove firmware:
      0=Off, 1=Manual RGB, 2=Follow, 3=Breathing, 4=Rainbow
  - Demo modes replicate behaviors seen in task_led.py examples.
  - temp-follow uses a blue->red gradient based on temperature.
EOF
}

preset_rgb() {
  case "$1" in
    red) echo "255 0 0" ;;
    green) echo "0 255 0" ;;
    blue) echo "0 0 255" ;;
    orange) echo "255 165 0" ;;
    yellow) echo "255 255 0" ;;
    white) echo "255 255 255" ;;
    purple) echo "128 0 128" ;;
    cyan) echo "0 255 255" ;;
    magenta) echo "255 0 255" ;;
    pink) echo "255 105 180" ;;
    teal) echo "0 128 128" ;;
    indigo) echo "75 0 130" ;;
    lime) echo "50 205 50" ;;
    gold) echo "255 215 0" ;;
    amber) echo "255 191 0" ;;
    warmwhite) echo "255 244 229" ;;
    coolwhite) echo "230 245 255" ;;
    *) return 1 ;;
  esac
}

list_presets() {
  cat <<'EOF'
Available presets:
  red green blue orange yellow white purple cyan magenta
  pink teal indigo lime gold amber warmwhite coolwhite
EOF
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

cmd="$1"
shift

persist=0
code_dir_override=""
REMAINING_ARGS=()

parse_common_flags() {
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
  REMAINING_ARGS=("$@")
}

run_python() {
  local code_dir="$1"
  shift
  python_run_with_code_dir "$code_dir" - "$@"
}

case "$cmd" in
  -h|--help)
    usage
    exit 0
    ;;

  get)
    parse_common_flags "$@"
    set -- "${REMAINING_ARGS[@]}"
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
led = data.get("LED", {})
print(f"Config file: {cfg}")
print("LED configured values (software config):")
for key in [
    "mode", "red_value", "green_value", "blue_value",
    "task_name", "is_run_on_startup"
]:
    if key in led:
        print(f"- {key}: {led[key]}")
PY
    ;;

  read|status)
    parse_common_flags "$@"
    set -- "${REMAINING_ARGS[@]}"
    code_dir="$(resolve_freenove_code_dir "$code_dir_override")"
    run_python "$code_dir" <<PY
from api_expansion import Expansion

exp = Expansion()
try:
    mode = exp.get_led_mode()
    colors = exp.get_all_led_color()
    mode_name = {
        0: "off",
        1: "manual",
        2: "follow",
        3: "breathing",
        4: "rainbow",
    }.get(mode, "unknown")
    grouped = [tuple(colors[i:i+3]) for i in range(0, len(colors), 3)]
    print(f"LED mode (hardware): {mode} ({mode_name})")
    print(f"All LED colors raw (18 bytes): {colors}")
    print(f"LED colors grouped (6 LEDs): {grouped}")
finally:
    exp.end()
PY
    ;;

  list-presets)
    list_presets
    ;;

  preset)
    if [[ $# -lt 1 ]]; then
      echo "Missing preset name. Use: preset <name>" >&2
      exit 1
    fi
    name="${1,,}"
    shift
    if ! rgb="$(preset_rgb "$name")"; then
      echo "Unknown preset: $name" >&2
      list_presets
      exit 1
    fi
    read -r r g b <<<"$rgb"
    parse_common_flags "$@"
    set -- "${REMAINING_ARGS[@]}"
    code_dir="$(resolve_freenove_code_dir "$code_dir_override")"

    run_python "$code_dir" <<PY
from api_expansion import Expansion
exp = Expansion()
try:
    exp.set_led_mode(1)
    exp.set_all_led_color(${r}, ${g}, ${b})
    if ${persist}:
        exp.set_save_flash(1)
    print("Set preset ${name} -> (${r}, ${g}, ${b})")
finally:
    exp.end()
PY
    ;;

  off)
    parse_common_flags "$@"
    set -- "${REMAINING_ARGS[@]}"
    code_dir="$(resolve_freenove_code_dir "$code_dir_override")"
    run_python "$code_dir" <<PY
from api_expansion import Expansion
exp = Expansion()
try:
    exp.set_led_mode(0)
    exp.set_all_led_color(0, 0, 0)
    if ${persist}:
        exp.set_save_flash(1)
    print("LEDs turned off")
finally:
    exp.end()
PY
    ;;

  rainbow)
    parse_common_flags "$@"
    set -- "${REMAINING_ARGS[@]}"
    code_dir="$(resolve_freenove_code_dir "$code_dir_override")"
    run_python "$code_dir" <<PY
from api_expansion import Expansion
exp = Expansion()
try:
    exp.set_led_mode(4)
    if ${persist}:
        exp.set_save_flash(1)
    print("LED rainbow mode enabled")
finally:
    exp.end()
PY
    ;;

  floating-rainbow)
    parse_common_flags "$@"
    set -- "${REMAINING_ARGS[@]}"
    code_dir="$(resolve_freenove_code_dir "$code_dir_override")"
    run_python "$code_dir" <<PY
from api_expansion import Expansion
exp = Expansion()
try:
    exp.set_led_mode(2)
    exp.set_all_led_color(0, 180, 255)
    if ${persist}:
        exp.set_save_flash(1)
    print("LED follow mode enabled (floating-rainbow style)")
finally:
    exp.end()
PY
    ;;

  manual|breathing|follow)
    if [[ $# -lt 3 ]]; then
      echo "Missing color arguments. Use: $cmd <R> <G> <B>" >&2
      exit 1
    fi
    r="$1"; g="$2"; b="$3"; shift 3
    for v in "$r" "$g" "$b"; do
      if [[ ! "$v" =~ ^[0-9]+$ ]] || (( v < 0 || v > 255 )); then
        echo "Color values must be integers 0..255" >&2
        exit 1
      fi
    done
    parse_common_flags "$@"
    set -- "${REMAINING_ARGS[@]}"
    code_dir="$(resolve_freenove_code_dir "$code_dir_override")"

    case "$cmd" in
      manual) mode=1 ;;
      breathing) mode=3 ;;
      follow) mode=2 ;;
    esac

    run_python "$code_dir" <<PY
from api_expansion import Expansion
exp = Expansion()
try:
    exp.set_led_mode(${mode})
    exp.set_all_led_color(${r}, ${g}, ${b})
    if ${persist}:
        exp.set_save_flash(1)
    print("Set mode ${cmd} with color (${r}, ${g}, ${b})")
finally:
    exp.end()
PY
    ;;

  demo-wheel|demo-palette)
    duration="${1:-15}"
    if [[ ! "$duration" =~ ^[0-9]+$ ]] || (( duration <= 0 )); then
      echo "Duration must be a positive integer (seconds)." >&2
      exit 1
    fi
    shift || true
    parse_common_flags "$@"
    set -- "${REMAINING_ARGS[@]}"
    code_dir="$(resolve_freenove_code_dir "$code_dir_override")"

    run_python "$code_dir" <<PY
import time
from api_expansion import Expansion

cmd = "${cmd}"
duration = ${duration}

def wheel(pos):
    pos = pos % 255
    if pos < 85:
        return 255 - pos * 3, pos * 3, 0
    if pos < 170:
        pos -= 85
        return 0, 255 - pos * 3, pos * 3
    pos -= 170
    return pos * 3, 0, 255 - pos * 3

palette = [
    (255, 0, 0), (0, 255, 0), (0, 0, 255), (255, 255, 0),
    (75, 0, 130), (0, 255, 255), (255, 165, 0), (128, 0, 128),
    (255, 192, 203), (0, 128, 128), (64, 0, 128), (255, 0, 255),
]

exp = Expansion()
try:
    exp.set_led_mode(1)
    end = time.time() + duration
    if cmd == "demo-wheel":
        i = 0
        while time.time() < end:
            r, g, b = wheel(i)
            exp.set_all_led_color(r, g, b)
            time.sleep(0.05)
            i += 1
    else:
        i = 0
        while time.time() < end:
            r, g, b = palette[i % len(palette)]
            exp.set_all_led_color(r, g, b)
            time.sleep(0.5)
            i += 1
    print(f"Completed {cmd} for {duration}s")
finally:
    exp.end()
PY
    ;;

  temp-follow)
    sensor="cpu"
    cold=35
    hot=75
    interval="1.0"
    duration=0

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --sensor)
          sensor="${2:-}"
          shift 2
          ;;
        --cold)
          cold="${2:-}"
          shift 2
          ;;
        --hot)
          hot="${2:-}"
          shift 2
          ;;
        --interval)
          interval="${2:-}"
          shift 2
          ;;
        --duration)
          duration="${2:-}"
          shift 2
          ;;
        --persist|--code-dir)
          parse_common_flags "$@"
          set -- "${REMAINING_ARGS[@]}"
          break
          ;;
        *)
          echo "Unknown argument for temp-follow: $1" >&2
          exit 1
          ;;
      esac
    done

    if [[ "$sensor" != "cpu" && "$sensor" != "case" ]]; then
      echo "--sensor must be cpu or case" >&2
      exit 1
    fi
    if [[ ! "$cold" =~ ^[0-9]+([.][0-9]+)?$ ]] || [[ ! "$hot" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
      echo "--cold and --hot must be numeric values." >&2
      exit 1
    fi
    if [[ ! "$interval" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
      echo "--interval must be numeric seconds." >&2
      exit 1
    fi
    if [[ ! "$duration" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
      echo "--duration must be numeric seconds (0 = run forever)." >&2
      exit 1
    fi

    code_dir="$(resolve_freenove_code_dir "$code_dir_override")"

    run_python "$code_dir" <<PY
import time
from api_expansion import Expansion
from api_systemInfo import SystemInformation

sensor = "${sensor}"
cold = float(${cold})
hot = float(${hot})
interval = float(${interval})
duration = float(${duration})
persist = ${persist}

if hot <= cold:
    raise SystemExit("--hot must be greater than --cold")

def clamp(v, lo, hi):
    return max(lo, min(hi, v))

def color_from_temp(temp):
    ratio = clamp((temp - cold) / (hot - cold), 0.0, 1.0)
    r = int(round(255 * ratio))
    g = 0
    b = int(round(255 * (1.0 - ratio)))
    return r, g, b, ratio

exp = Expansion()
sysinfo = SystemInformation()

try:
    exp.set_led_mode(1)
    if persist:
        exp.set_save_flash(1)

    start = time.time()
    while True:
        if sensor == "cpu":
            temp = float(sysinfo.get_raspberry_pi_cpu_temperature())
        else:
            temp = float(exp.get_temp())

        r, g, b, ratio = color_from_temp(temp)
        exp.set_all_led_color(r, g, b)
        print(f"sensor={sensor} temp={temp:.1f}C ratio={ratio:.2f} color=({r},{g},{b})")

        if duration > 0 and (time.time() - start) >= duration:
            break
        time.sleep(interval)
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
