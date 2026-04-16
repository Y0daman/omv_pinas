#!/usr/bin/env bash
set -euo pipefail

resolve_freenove_code_dir() {
  local requested="${1:-${FREENOVE_CODE_DIR:-}}"
  local -a candidates=()
  local home_dir="${HOME:-}"
  local user_name="${USER:-}"

  if [[ -n "$requested" ]]; then
    candidates+=("$requested")
  fi

  candidates+=("/home/jimmy/git/omv_pinas/scripts/freenove")

  if [[ -n "$home_dir" ]]; then
    candidates+=("$home_dir/git/omv_pinas/scripts/freenove")
  fi

  candidates+=("/opt/omv_pinas/scripts/freenove")

  if [[ -n "$user_name" ]]; then
    candidates+=("/home/$user_name/git/omv_pinas/scripts/freenove")
  fi

  # Legacy fallback paths
  candidates+=("/Volumes/CEVAULT512/git/Freenove_Computer_Case_Kit_Pro_for_Raspberry_Pi/Code")
  if [[ -n "$home_dir" ]]; then
    candidates+=("$home_dir/git/Freenove_Computer_Case_Kit_Pro_for_Raspberry_Pi/Code")
  fi
  candidates+=("/opt/Freenove_Computer_Case_Kit_Pro_for_Raspberry_Pi/Code")
  if [[ -n "$user_name" ]]; then
    candidates+=("/home/$user_name/Freenove_Computer_Case_Kit_Pro_for_Raspberry_Pi/Code")
  fi

  local dir
  for dir in "${candidates[@]}"; do
    if [[ -n "$dir" && -d "$dir" && -f "$dir/api_expansion.py" ]]; then
      printf '%s\n' "$dir"
      return 0
    fi
  done

  echo "Could not find Freenove Code directory." >&2
  echo "Set FREENOVE_CODE_DIR or pass --code-dir <path>." >&2
  return 1
}

python_run_with_code_dir() {
  local code_dir="$1"
  shift
  PYTHONPATH="$code_dir${PYTHONPATH:+:$PYTHONPATH}" python3 "$@"
}

resolve_freenove_config_file() {
  local code_dir="$1"
  printf '%s\n' "$code_dir/app_config.json"
}

ensure_freenove_config_exists() {
  local code_dir="$1"
  local cfg
  cfg="$(resolve_freenove_config_file "$code_dir")"

  if [[ -f "$cfg" ]]; then
    return 0
  fi

  echo "Config file missing, creating defaults: $cfg" >&2
  python_run_with_code_dir "$code_dir" - <<PY
from api_json import ConfigManager

cfg = "${cfg}"
cm = ConfigManager(cfg)
cm.save_config()
print(f"Created config: {cfg}")
PY
}
