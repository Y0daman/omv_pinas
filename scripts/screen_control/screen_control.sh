#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../hw/common.sh
source "$SCRIPT_DIR/../hw/common.sh"

usage() {
  cat <<'EOF'
Control Freenove large-screen UI apps.

Usage:
  screen_control.sh <command> [options]

Commands:
  get
  read
  status
  info
  set-orientation
  run-dashboard
  run-monitor
  run-dashboard-virtual
  run-monitor-virtual

Options:
  --backend <auto|x11|wayland|eglfs|linuxfb>
  --rotation <0|90|180|270>
  --orientation <0|90|180|270>
  --touch-flags <none|invx|invy|swapxy|comma-list>
  --fullscreen
  --virtual-size <WIDTHxHEIGHT|auto>
  --vnc-port <port>
  --code-dir <path>
  --apply-boot-config
  --boot-config <path>
  --overlay <name>

Notes:
  - app_ui.py and app_ui_monitor.py are PyQt5 applications.
  - They need a graphics stack. In headless SSH sessions, there is no display unless
    you provide one (X11 forwarding, Wayland, eglfs, or linuxfb).
EOF
}

if [[ $# -lt 1 ]] || [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
  usage
  exit 1
fi

cmd="$1"
shift

backend="auto"
fullscreen=0
code_dir_override=""
rotation=""
orientation=""
touch_flags=""
virtual_size="auto"
vnc_port="5901"
apply_boot_config=0
boot_config_path="/boot/firmware/config.txt"
overlay_name="vc4-kms-dsi-ili9881-7inch"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --backend)
      backend="${2:-auto}"
      shift 2
      ;;
    --rotation)
      rotation="${2:-}"
      shift 2
      ;;
    --orientation)
      orientation="${2:-}"
      shift 2
      ;;
    --touch-flags)
      touch_flags="${2:-}"
      shift 2
      ;;
    --fullscreen)
      fullscreen=1
      shift
      ;;
    --virtual-size)
      virtual_size="${2:-auto}"
      shift 2
      ;;
    --vnc-port)
      vnc_port="${2:-5901}"
      shift 2
      ;;
    --code-dir)
      code_dir_override="${2:-}"
      shift 2
      ;;
    --apply-boot-config)
      apply_boot_config=1
      shift
      ;;
    --boot-config)
      boot_config_path="${2:-}"
      shift 2
      ;;
    --overlay)
      overlay_name="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

code_dir="$(resolve_freenove_code_dir "$code_dir_override")"

if [[ -n "$rotation" && ! "$rotation" =~ ^(0|90|180|270)$ ]]; then
  echo "--rotation must be one of: 0,90,180,270" >&2
  exit 1
fi

if [[ -n "$orientation" && ! "$orientation" =~ ^(0|90|180|270)$ ]]; then
  echo "--orientation must be one of: 0,90,180,270" >&2
  exit 1
fi

if [[ "$virtual_size" != "auto" ]] && [[ ! "$virtual_size" =~ ^[0-9]+x[0-9]+$ ]]; then
  echo "--virtual-size must be WIDTHxHEIGHT or auto" >&2
  exit 1
fi

if [[ ! "$vnc_port" =~ ^[0-9]+$ ]]; then
  echo "--vnc-port must be numeric" >&2
  exit 1
fi

normalize_touch_flags() {
  local raw="$1"
  if [[ -z "$raw" || "$raw" == "none" ]]; then
    printf '%s\n' ""
    return 0
  fi

  local out=""
  local token
  local -a arr=()
  IFS=',' read -r -a arr <<<"$raw"
  for token in "${arr[@]}"; do
    token="${token// /}"
    case "$token" in
      invx|invy|swapxy)
        if [[ -n "$out" ]]; then
          out+=","
        fi
        out+="$token"
        ;;
      "") ;;
      *)
        echo "--touch-flags supports only: invx,invy,swapxy or none" >&2
        return 1
        ;;
    esac
  done

  printf '%s\n' "$out"
}

touch_flags_normalized="$(normalize_touch_flags "$touch_flags")"

resolve_qpa_platform() {
  local requested="$1"
  case "$requested" in
    auto)
      if [[ -n "${DISPLAY:-}" ]]; then
        echo "xcb"
      elif [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
        echo "wayland"
      else
        echo "eglfs"
      fi
      ;;
    x11) echo "xcb" ;;
    wayland|eglfs|linuxfb) echo "$requested" ;;
    *)
      echo "Invalid backend: $requested" >&2
      exit 1
      ;;
  esac
}

qpa_platform="$(resolve_qpa_platform "$backend")"

launch_qt_app() {
  local app="$1"
  local platform="$2"
  local use_fallback="$3"

  export PYTHONPATH="$code_dir${PYTHONPATH:+:$PYTHONPATH}"
  export QT_QPA_PLATFORM="$platform"
  export QT_QPA_EGLFS_HIDECURSOR=1
  export QT_QPA_EGLFS_DISABLE_INPUT=1
  if [[ -n "$rotation" ]]; then
    export QT_QPA_EGLFS_ROTATION="$rotation"
  fi
  if (( fullscreen == 1 )); then
    export QT_QPA_EGLFS_ALWAYS_SET_MODE=1
  fi

  echo "Launching $app with QT_QPA_PLATFORM=$QT_QPA_PLATFORM"
  echo "Working directory: $code_dir"
  cd "$code_dir"

  if [[ "$use_fallback" == "1" ]]; then
    set +e
    python3 "$app"
    rc=$?
    set -e
    if (( rc == 139 )) && [[ "$platform" == "eglfs" || "$platform" == "linuxfb" ]]; then
      echo "Detected segfault on $platform. Retrying with linuxfb + hidden cursor..."
      export QT_QPA_PLATFORM="linuxfb"
      python3 "$app"
      return $?
    fi
    return $rc
  else
    exec python3 "$app"
  fi
}

launch_virtual_preview() {
  local app="$1"
  local resolved_size
  local width
  local height

  detect_virtual_size() {
    if [[ "$virtual_size" != "auto" ]]; then
      printf '%s\n' "$virtual_size"
      return 0
    fi

    if [[ -r /sys/class/graphics/fb0/virtual_size ]]; then
      local fb
      fb="$(cat /sys/class/graphics/fb0/virtual_size 2>/dev/null || true)"
      if [[ "$fb" =~ ^[0-9]+,[0-9]+$ ]]; then
        printf '%s\n' "${fb/,/x}"
        return 0
      fi
    fi

    printf '%s\n' "800x480"
  }

  resolved_size="$(detect_virtual_size)"
  width="${resolved_size%x*}"
  height="${resolved_size#*x}"

  if ! command -v Xvfb >/dev/null 2>&1; then
    echo "Xvfb is required. Install: sudo apt-get install -y xvfb x11vnc" >&2
    exit 1
  fi
  if ! command -v x11vnc >/dev/null 2>&1; then
    echo "x11vnc is required. Install: sudo apt-get install -y x11vnc" >&2
    exit 1
  fi

  export PYTHONPATH="$code_dir${PYTHONPATH:+:$PYTHONPATH}"
  export DISPLAY=:99
  export QT_QPA_PLATFORM=xcb

  echo "Starting virtual display ${DISPLAY} (${width}x${height})"
  Xvfb "$DISPLAY" -screen 0 "${width}x${height}x24" >/tmp/xvfb.log 2>&1 &
  xvfb_pid=$!

  cleanup() {
    kill "$app_pid" >/dev/null 2>&1 || true
    kill "$vnc_pid" >/dev/null 2>&1 || true
    kill "$xvfb_pid" >/dev/null 2>&1 || true
  }
  trap cleanup EXIT INT TERM

  cd "$code_dir"
  python3 "$app" >/tmp/freenove_virtual_app.log 2>&1 &
  app_pid=$!

  x11vnc -display "$DISPLAY" -rfbport "$vnc_port" -forever -shared -nopw >/tmp/freenove_virtual_vnc.log 2>&1 &
  vnc_pid=$!

  echo "Virtual preview is running."
  echo "Connect with a VNC client to: <pi-ip>:${vnc_port}"
  echo "App log: /tmp/freenove_virtual_app.log"
  echo "VNC log: /tmp/freenove_virtual_vnc.log"
  wait "$app_pid"
}

case "$cmd" in
  get)
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
monitor = data.get("Monitor", {})
print(f"Config file: {cfg}")
print("Screen configured values (software config):")
for key in ["screen_orientation", "follow_led_color"]:
    if key in monitor:
        print(f"- {key}: {monitor[key]}")
PY
    ;;

  read|status)
    echo "Screen runtime read:"
    echo "- Freenove Code dir: $code_dir"
    echo "- DISPLAY: ${DISPLAY:-<unset>}"
    echo "- WAYLAND_DISPLAY: ${WAYLAND_DISPLAY:-<unset>}"
    echo "- XDG_RUNTIME_DIR: ${XDG_RUNTIME_DIR:-<unset>}"
    echo "- Suggested QT_QPA_PLATFORM: $qpa_platform"
    if command -v xrandr >/dev/null 2>&1; then
      xr="$(xrandr --current 2>/dev/null || true)"
      if [[ -n "$xr" ]]; then
        echo "- xrandr output:"
        printf '%s\n' "$xr"
      fi
    fi
    if [[ -r /sys/class/graphics/fb0/virtual_size ]]; then
      echo "- fb0 virtual_size: $(cat /sys/class/graphics/fb0/virtual_size)"
    fi
    if [[ -r /sys/class/drm/card0-HDMI-A-1/status ]]; then
      echo "- HDMI-A-1 status: $(cat /sys/class/drm/card0-HDMI-A-1/status)"
    fi
    ;;

  info)
    echo "Freenove Code dir: $code_dir"
    echo "DISPLAY: ${DISPLAY:-<unset>}"
    echo "WAYLAND_DISPLAY: ${WAYLAND_DISPLAY:-<unset>}"
    echo "XDG_RUNTIME_DIR: ${XDG_RUNTIME_DIR:-<unset>}"
    echo "Recommended QT_QPA_PLATFORM now: $qpa_platform"
    echo
    echo "Can run without desktop?"
    echo "- Yes, potentially, via Qt backends like eglfs/linuxfb on a local console (tty)."
    echo "- Over plain SSH (no forwarded display), GUI windows are not visible remotely."
    echo "- OLED and fan/LED control scripts work fully headless."
    ;;

  set-orientation)
    if [[ -z "$orientation" ]]; then
      echo "set-orientation requires --orientation <0|90|180|270>" >&2
      exit 1
    fi

    ensure_freenove_config_exists "$code_dir"
    cfg_file="$(resolve_freenove_config_file "$code_dir")"

    monitor_orientation="0"
    if [[ "$orientation" == "90" || "$orientation" == "270" ]]; then
      monitor_orientation="1"
    fi

    python3 - <<PY
import json
from pathlib import Path

cfg = Path("${cfg_file}")
if not cfg.exists():
    print(f"Missing config file: {cfg}")
    raise SystemExit(1)

data = json.loads(cfg.read_text(encoding="utf-8"))
monitor = data.setdefault("Monitor", {})
monitor["screen_orientation"] = int("${monitor_orientation}")
cfg.write_text(json.dumps(data, indent=2), encoding="utf-8")
print(f"Updated {cfg}")
print(f"- Monitor.screen_orientation: {monitor['screen_orientation']} (0=landscape, 1=portrait)")
PY

    if (( apply_boot_config == 1 )); then
      boot_parent="$(dirname "$boot_config_path")"
      if [[ ! -d "$boot_parent" ]]; then
        echo "Parent directory does not exist: $boot_parent" >&2
        exit 1
      fi

      if [[ -e "$boot_config_path" && ! -w "$boot_config_path" ]]; then
        echo "No write access to $boot_config_path (try with sudo)." >&2
        exit 1
      fi

      python3 - <<PY
from pathlib import Path

boot_cfg = Path("${boot_config_path}")
overlay = "${overlay_name}"
rotation = "${orientation}"
touch = "${touch_flags_normalized}"

if boot_cfg.exists():
    lines = boot_cfg.read_text(encoding="utf-8").splitlines()
else:
    lines = []

new_line = f"dtoverlay={overlay},rotation={rotation}"
if touch:
    new_line = f"{new_line},{touch}"

replaced = False
prefix = f"dtoverlay={overlay}"
for i, line in enumerate(lines):
    if line.strip().startswith(prefix):
        lines[i] = new_line
        replaced = True

if not replaced:
    lines.append(new_line)

boot_cfg.write_text("\n".join(lines).rstrip("\n") + "\n", encoding="utf-8")
print(f"Updated {boot_cfg}")
print(f"- {new_line}")
PY
    else
      echo "Boot config not changed (add --apply-boot-config to update ${boot_config_path})."
      line="dtoverlay=${overlay_name},rotation=${orientation}"
      if [[ -n "$touch_flags_normalized" ]]; then
        line+="${line:+,}${touch_flags_normalized}"
      fi
      echo "Recommended config.txt line: $line"
    fi

    echo "Touch flag hint:" 
    echo "- Start with none, then try: swapxy, swapxy,invy, or swapxy,invx if touch axis is wrong."
    ;;

  run-dashboard|run-monitor|run-dashboard-virtual|run-monitor-virtual)
    app="app_ui.py"
    if [[ "$cmd" == "run-monitor" || "$cmd" == "run-monitor-virtual" ]]; then
      app="app_ui_monitor.py"
    fi

    if [[ ! -f "$code_dir/$app" ]]; then
      echo "Missing application: $code_dir/$app" >&2
      exit 1
    fi

    if [[ "$cmd" == *"-virtual" ]]; then
      launch_virtual_preview "$app"
    else
      launch_qt_app "$app" "$qpa_platform" 1
    fi
    ;;

  *)
    echo "Unknown command: $cmd" >&2
    usage
    exit 1
    ;;
esac
