#!/usr/bin/env bash

# Default run-commands directories
# Installed defaults (deployed by install.sh / update.sh from examples/run-commands/)
_SSM_RUN_INSTALL_DIR="${HOME}/.local/share/aws-ssm-tools/run-commands"
# User-defined commands (never overwritten by install/update)
_SSM_RUN_USER_DIR="${HOME}/.config/aws-ssm-tools/run-commands"

ssm_run_usage() {
  cat <<EOF
Usage: ssm run [flags] <name|command> [filter]

Run a command or script against one or more AWS profiles.

Flags:
  -q <command>   Run an inline AWS command (with optional filter)
  -d <path>      Use only this commands directory (overrides defaults)
  -h, --help     Show this help message

Filters:
  Space-separated profile names or profile:region pairs.
  When no filter is provided, saved commands iterate all profiles.
  When no region is specified, us-east-1 is used by default.

Snippet placeholders:
  #ENV     Replaced with the current profile name
  #REGION  Replaced with the current region

Command directories (in priority order):
  ${_SSM_RUN_INSTALL_DIR}
  ${_SSM_RUN_USER_DIR}

Examples:
  ssm run                                    # List available commands
  ssm run vpc-cidrs "fail how"               # Run snippet across profiles
  ssm run instances                          # Run executable script
  ssm run instances "wtf:us-west-2"          # Run script for specific profile/region
  ssm run -q "aws s3 ls" "wtf ninja"         # Inline query across profiles
  ssm run -d /path/to/commands my-script     # Custom commands directory
EOF
}

# List commands merged from one or more directories.
# Dirs are given in ascending priority order — later entries override earlier ones.
ssm_run_list_commands() {
  local -a dirs=("$@")
  local -A cmd_desc cmd_marks

  for dir in "${dirs[@]}"; do
    [[ -d "$dir" ]] || continue
    local is_user=false
    [[ "$dir" == "$_SSM_RUN_USER_DIR" ]] && is_user=true

    for f in "$dir"/*; do
      [[ -f "$f" ]] || continue
      local name
      name=$(basename "$f")
      local desc
      desc=$(sed -n '2s/^# *//p' "$f")
      local marks=""
      [[ -x "$f" ]] && marks="*"
      $is_user && marks="${marks}+"
      cmd_desc["$name"]="$desc"
      cmd_marks["$name"]="$marks"
    done
  done

  if [[ ${#cmd_desc[@]} -eq 0 ]]; then
    echo "No commands found."
    return 0
  fi

  echo "Available commands:"
  echo ""

  local name
  while IFS= read -r name; do
    printf "  %-22s %s%s\n" "$name" "${cmd_desc[$name]}" "${cmd_marks[$name]}"
  done < <(printf '%s\n' "${!cmd_desc[@]}" | sort)

  echo ""
  # Build legend only from markers that are actually in use
  local legend=""
  local name
  for name in "${!cmd_marks[@]}"; do
    [[ "${cmd_marks[$name]}" == *"*"* ]] && legend="* = executable script" && break
  done
  for name in "${!cmd_marks[@]}"; do
    if [[ "${cmd_marks[$name]}" == *"+"* ]]; then
      [[ -n "$legend" ]] && legend="${legend}    "
      legend="${legend}+ = user-defined"
      break
    fi
  done
  [[ -n "$legend" ]] && echo "  $legend" && echo ""
  echo "Run 'ssm run --help' for usage examples."
}

# Resolve the script file for a command name.
# Dirs are checked from last to first (highest priority first).
ssm_run_resolve_script() {
  local name="$1"
  shift
  local -a dirs=("$@")
  local i
  for (( i=${#dirs[@]}-1; i>=0; i-- )); do
    local f="${dirs[$i]}/$name"
    [[ -f "$f" ]] && echo "$f" && return 0
  done
  return 1
}

ssm_run() {
  local query="" custom_dir=""
  local positionals=()

  # Parse flags — we handle -q and -d ourselves, pass rest through
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -q) query="$2"; shift 2 ;;
      -d) custom_dir="$2"; shift 2 ;;
      -h|--help) ssm_run_usage; return 0 ;;
      *)  positionals+=("$1"); shift ;;
    esac
  done
  set -- "${positionals[@]+${positionals[@]}}"

  # Build the list of command directories to search.
  # -d flag or AWS_TOOLS_CMD_DIR override: use only that directory (exclusive).
  # Otherwise: merge installed defaults + user dir (user takes precedence).
  local -a cmd_dirs=()
  if [[ -n "$custom_dir" ]]; then
    if [[ ! -d "$custom_dir" ]]; then
      log_error "Commands directory not found: $custom_dir"
      return 1
    fi
    cmd_dirs=("$custom_dir")
  elif [[ -n "${AWS_TOOLS_CMD_DIR:-}" ]]; then
    if [[ ! -d "$AWS_TOOLS_CMD_DIR" ]]; then
      log_error "Commands directory not found: $AWS_TOOLS_CMD_DIR"
      return 1
    fi
    cmd_dirs=("$AWS_TOOLS_CMD_DIR")
  else
    [[ -d "$_SSM_RUN_INSTALL_DIR" ]] && cmd_dirs+=("$_SSM_RUN_INSTALL_DIR")
    [[ -d "$_SSM_RUN_USER_DIR" ]]    && cmd_dirs+=("$_SSM_RUN_USER_DIR")
  fi

  # Quick query — treat as an inline command (supports optional filter)
  if [[ -n "$query" ]]; then
    set -- "$query" "$@"
  fi

  # No args: list available commands
  if [[ -z "${1:-}" ]]; then
    if [[ ${#cmd_dirs[@]} -eq 0 ]]; then
      log_error "No run-commands directories found."
      log_error "Expected: $_SSM_RUN_INSTALL_DIR"
      log_error "Set AWS_TOOLS_CMD_DIR or use -d <path>"
      return 1
    fi
    ssm_run_list_commands "${cmd_dirs[@]}"
    return 0
  fi

  local name="$1"

  # Resolve script: user dir takes precedence over installed defaults
  local script=""
  script=$(ssm_run_resolve_script "$name" "${cmd_dirs[@]}" 2>/dev/null) || true

  local is_executable=false
  [[ -n "$script" && -x "$script" ]] && is_executable=true

  # Executable script with no filter — run directly (no profile iteration)
  if $is_executable && [[ -z "${2:-}" ]]; then
    shift
    "$script" "$@"
    return
  fi

  # Resolve command text from snippet file or use raw command string
  local command="$name"
  if [[ -n "$script" ]] && ! $is_executable; then
    command=$(sed '/^#/d; /^$/d' "$script")
  fi

  # Build profile entries from filter or list all profiles
  local entries=()
  if [[ -n "${2:-}" ]]; then
    read -r -a entries <<< "$2"
  else
    mapfile -t entries < <(aws_list_profiles)
  fi

  if [[ ${#entries[@]} -eq 0 ]]; then
    log_error "No profiles found"
    return 1
  fi

  # Iterate profiles, assuming into each one
  for entry in "${entries[@]}"; do
    local profile="${entry%%:*}"
    local region="${entry#*:}"
    [[ "$region" == "$entry" ]] && region="us-east-1"

    aws_auth_login "$profile" "$region" || {
      log_warn "Failed to assume '$profile', skipping"
      continue
    }

    echo "$profile"

    if $is_executable; then
      "$script"
    else
      local cmd="${command/'#ENV'/$profile}"
      cmd="${cmd/'#REGION'/$region}"
      eval "$cmd"
    fi
  done
}
