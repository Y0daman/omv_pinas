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
  info
  run-dashboard
  run-monitor

Options:
  --backend <auto|x11|wayland|eglfs|linuxfb>
  --fullscreen
  --code-dir <path>

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

while [[ $# -gt 0 ]]; do
  case "$1" in
    --backend)
      backend="${2:-auto}"
      shift 2
      ;;
    --fullscreen)
      fullscreen=1
      shift
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
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

code_dir="$(resolve_freenove_code_dir "$code_dir_override")"

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

case "$cmd" in
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

  run-dashboard|run-monitor)
    app="app_ui.py"
    if [[ "$cmd" == "run-monitor" ]]; then
      app="app_ui_monitor.py"
    fi

    if [[ ! -f "$code_dir/$app" ]]; then
      echo "Missing application: $code_dir/$app" >&2
      exit 1
    fi

    export PYTHONPATH="$code_dir${PYTHONPATH:+:$PYTHONPATH}"
    export QT_QPA_PLATFORM="$qpa_platform"
    if (( fullscreen == 1 )); then
      export QT_QPA_EGLFS_ALWAYS_SET_MODE=1
    fi

    echo "Launching $app with QT_QPA_PLATFORM=$QT_QPA_PLATFORM"
    echo "Working directory: $code_dir"
    cd "$code_dir"
    exec python3 "$app"
    ;;

  *)
    echo "Unknown command: $cmd" >&2
    usage
    exit 1
    ;;
esac
