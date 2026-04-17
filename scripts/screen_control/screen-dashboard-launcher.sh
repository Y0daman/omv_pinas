#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCREEN_CONTROL_SH="$REPO_ROOT/scripts/screen_control/screen_control.sh"

if [[ ! -x "$SCREEN_CONTROL_SH" ]]; then
  echo "Missing executable screen control script: $SCREEN_CONTROL_SH" >&2
  exit 1
fi

backend="${SCREEN_BACKEND:-linuxfb}"
rotation="${SCREEN_ROTATION:-}"
code_dir="${FREENOVE_CODE_DIR:-}"
clean_stale="${SCREEN_CLEAN_STALE:-1}"

if [[ "$clean_stale" == "1" ]]; then
  pkill -f '/app_ui.py' >/dev/null 2>&1 || true
  pkill -f '/task_oled.py' >/dev/null 2>&1 || true
fi

args=(run-dashboard --backend "$backend")
if [[ -n "$rotation" ]]; then
  args+=(--rotation "$rotation")
fi
if [[ -n "$code_dir" ]]; then
  args+=(--code-dir "$code_dir")
fi

exec "$SCREEN_CONTROL_SH" "${args[@]}"
