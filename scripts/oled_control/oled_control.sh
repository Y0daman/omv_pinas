#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../hw/common.sh
source "$SCRIPT_DIR/../hw/common.sh"

usage() {
  cat <<'EOF'
Control OLED pages used by task_oled.py.

Usage:
  oled_control.sh <command> [options]

Commands:
  list
  get
  read
  status
  show <time|usage|temp|fan|all>
  enable <comma-separated-pages>
  disable <comma-separated-pages>
  start-task
  stop-task
  restart-task

Options:
  --code-dir <path>      Path to Freenove Code directory
  --restart-task         Restart task_oled.py after config changes

Pages:
  time   = Screen 1 (date/time/weekday)
  usage  = Screen 2 (IP + CPU/MEM/DISK)
  temp   = Screen 3 (Pi temp + Case temp)
  fan    = Screen 4 (Pi/C1/C2 PWM)
EOF
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

cmd="$1"
shift

code_dir_override=""
restart_task=0

parse_flags() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --code-dir)
        code_dir_override="${2:-}"
        shift 2
        ;;
      --restart-task)
        restart_task=1
        shift
        ;;
      *)
        break
        ;;
    esac
  done
  printf '%s\n' "$@"
}

restart_oled_task() {
  local code_dir="$1"
  (cd "$code_dir" && pkill -f "task_oled.py" >/dev/null 2>&1 || true)
  (cd "$code_dir" && nohup python3 task_oled.py >/tmp/task_oled.log 2>&1 &)
  echo "task_oled.py restarted (logs: /tmp/task_oled.log)"
}

map_pages_to_python_list() {
  local pages_csv="$1"
  local py="[]"
  IFS=',' read -r -a arr <<<"$pages_csv"
  for p in "${arr[@]}"; do
    p="${p// /}"
    case "$p" in
      time) py="${py%]} , 'time']" ;;
      usage) py="${py%]} , 'usage']" ;;
      temp) py="${py%]} , 'temp']" ;;
      fan) py="${py%]} , 'fan']" ;;
      all) py="['time','usage','temp','fan']" ;;
      "") ;;
      *)
        echo "Unknown page: $p" >&2
        exit 1
        ;;
    esac
  done
  printf '%s\n' "$py"
}

case "$cmd" in
  -h|--help)
    usage
    exit 0
    ;;

  list)
    cat <<'EOF'
Available OLED pages from Freenove task_oled.py:
  1) time  - Date, time, weekday
  2) usage - IP address + CPU/MEM/DISK usage circles
  3) temp  - Pi and case temperature dials
  4) fan   - Pi/C1/C2 PWM dials and percentages
EOF
    ;;

  get|status)
    set -- $(parse_flags "$@")
    code_dir="$(resolve_freenove_code_dir "$code_dir_override")"
    python_run_with_code_dir "$code_dir" - <<PY
import json
from pathlib import Path

cfg = Path("$code_dir") / "app_config.json"
if not cfg.exists():
    print(f"Missing config: {cfg}")
    raise SystemExit(1)

data = json.loads(cfg.read_text(encoding="utf-8"))
oled = data.get("OLED", {})
screens = {
    "time": oled.get("screen1", {}),
    "usage": oled.get("screen2", {}),
    "temp": oled.get("screen3", {}),
    "fan": oled.get("screen4", {}),
}

print(f"Config file: {cfg}")
print(f"OLED task configured on startup: {oled.get('is_run_on_startup', False)}")
for key, payload in screens.items():
    enabled = payload.get("is_run_on_oled", False)
    duration = payload.get("display_time", "n/a")
    print(f"- {key}: enabled={enabled}, display_time={duration}s")
PY
    ;;

  read)
    set -- $(parse_flags "$@")
    code_dir="$(resolve_freenove_code_dir "$code_dir_override")"
    python_run_with_code_dir "$code_dir" - <<'PY'
import os
import subprocess
from pathlib import Path

code_dir = Path("." ).resolve()
log_path = Path("/tmp/task_oled.log")

def run(cmd):
    try:
        return subprocess.check_output(cmd, text=True, stderr=subprocess.DEVNULL).strip()
    except Exception:
        return ""

pids = run(["pgrep", "-af", "task_oled.py"])
print("OLED runtime read:")
if pids:
    print("- task_oled.py process:")
    for line in pids.splitlines():
        print(f"  {line}")
else:
    print("- task_oled.py process: not running")

if log_path.exists():
    print(f"- log file: {log_path} ({log_path.stat().st_size} bytes)")
else:
    print(f"- log file: {log_path} (missing)")

if Path("/dev/i2c-1").exists():
    print("- i2c bus: /dev/i2c-1 present")
else:
    print("- i2c bus: /dev/i2c-1 missing")

print("- note: OLED pixel readback is not exposed by the board API")
PY
    ;;

  show|enable|disable)
    if [[ $# -lt 1 ]]; then
      echo "Missing page argument." >&2
      exit 1
    fi
    pages="$1"
    shift
    set -- $(parse_flags "$@")
    code_dir="$(resolve_freenove_code_dir "$code_dir_override")"
    pages_py="$(map_pages_to_python_list "$pages")"

    python_run_with_code_dir "$code_dir" - <<PY
import json
from pathlib import Path

cmd = "${cmd}"
selected = ${pages_py}

cfg = Path("$code_dir") / "app_config.json"
if not cfg.exists():
    print(f"Missing config: {cfg}")
    raise SystemExit(1)

data = json.loads(cfg.read_text(encoding="utf-8"))
oled = data.setdefault("OLED", {})
for idx in range(1, 5):
    oled.setdefault(f"screen{idx}", {})

mapping = {
    "time": "screen1",
    "usage": "screen2",
    "temp": "screen3",
    "fan": "screen4",
}

if cmd == "show":
    for k in mapping.values():
        oled[k]["is_run_on_oled"] = False
    for name in selected:
        oled[mapping[name]]["is_run_on_oled"] = True
elif cmd == "enable":
    for name in selected:
        oled[mapping[name]]["is_run_on_oled"] = True
elif cmd == "disable":
    for name in selected:
        oled[mapping[name]]["is_run_on_oled"] = False

cfg.write_text(json.dumps(data, indent=2), encoding="utf-8")
print(f"Updated OLED config in {cfg}")
PY

    if (( restart_task == 1 )); then
      restart_oled_task "$code_dir"
    else
      echo "Tip: add --restart-task to apply immediately."
    fi
    ;;

  start-task)
    set -- $(parse_flags "$@")
    code_dir="$(resolve_freenove_code_dir "$code_dir_override")"
    (cd "$code_dir" && nohup python3 task_oled.py >/tmp/task_oled.log 2>&1 &)
    echo "Started task_oled.py (logs: /tmp/task_oled.log)"
    ;;

  stop-task)
    set -- $(parse_flags "$@")
    code_dir="$(resolve_freenove_code_dir "$code_dir_override")"
    (cd "$code_dir" && pkill -f "task_oled.py" >/dev/null 2>&1 || true)
    echo "Stopped task_oled.py"
    ;;

  restart-task)
    set -- $(parse_flags "$@")
    code_dir="$(resolve_freenove_code_dir "$code_dir_override")"
    restart_oled_task "$code_dir"
    ;;

  *)
    echo "Unknown command: $cmd" >&2
    usage
    exit 1
    ;;
esac
