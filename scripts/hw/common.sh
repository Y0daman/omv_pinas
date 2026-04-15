#!/usr/bin/env bash
set -euo pipefail

resolve_freenove_code_dir() {
  local requested="${1:-${FREENOVE_CODE_DIR:-}}"
  local -a candidates=()

  if [[ -n "$requested" ]]; then
    candidates+=("$requested")
  fi

  candidates+=(
    "/Volumes/CEVAULT512/git/Freenove_Computer_Case_Kit_Pro_for_Raspberry_Pi/Code"
    "$HOME/git/Freenove_Computer_Case_Kit_Pro_for_Raspberry_Pi/Code"
    "/opt/Freenove_Computer_Case_Kit_Pro_for_Raspberry_Pi/Code"
    "/home/$USER/Freenove_Computer_Case_Kit_Pro_for_Raspberry_Pi/Code"
  )

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
