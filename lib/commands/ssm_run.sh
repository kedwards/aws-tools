#!/usr/bin/env bash

# Default commands directory
AWS_TOOLS_CMD_DIR="${AWS_TOOLS_CMD_DIR:-$HOME/.local/lib/aws-tools/commands}"

ssm_run_usage() {
  cat <<EOF
Usage: ssm run [flags] <name|command> [filter]

Run a command or script against one or more AWS profiles.

Flags:
  -q <command>   Run an inline AWS command (with optional filter)
  -d <path>      Override the commands directory
  -h, --help     Show this help message

Filters:
  Space-separated profile names or profile:region pairs.
  When no filter is provided, saved commands iterate all profiles.
  When no region is specified, us-east-1 is used by default.

Snippet placeholders:
  #ENV     Replaced with the current profile name
  #REGION  Replaced with the current region

Examples:
  ssm run                                    # List available commands
  ssm run vpc-cidrs "fail how"               # Run snippet across profiles
  ssm run instances                          # Run executable script
  ssm run instances "wtf:us-west-2"          # Run script for specific profile/region
  ssm run -q "aws s3 ls" "wtf ninja"         # Inline query across profiles
  ssm run -d /path/to/commands my-script     # Custom commands directory
EOF
}

ssm_run_list_commands() {
  local cmd_dir="$1"

  echo "Available commands ($cmd_dir):"
  echo ""

  for f in "$cmd_dir"/*; do
    [[ -f "$f" ]] || continue
    local desc
    desc=$(sed -n '2s/^# *//p' "$f")
    local marker=""
    [[ -x "$f" ]] && marker="*"
    printf "  %-20s %s%s\n" "$(basename "$f")" "$desc" "$marker"
  done

  echo ""
  echo "  * = executable script (run directly without profile iteration)"
  echo ""
  echo "Run 'ssm help' for usage examples."
}

ssm_run() {
  local cmd_dir="$AWS_TOOLS_CMD_DIR"
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

  [[ -n "$custom_dir" ]] && cmd_dir="$custom_dir"

  # Quick query — treat as an inline command (supports optional filter)
  if [[ -n "$query" ]]; then
    set -- "$query" "$@"
  fi

  # No args: list available commands
  if [[ -z "${1:-}" ]]; then
    if [[ -d "$cmd_dir" ]]; then
      ssm_run_list_commands "$cmd_dir"
    else
      log_error "Commands directory not found: $cmd_dir"
      log_error "Set AWS_TOOLS_CMD_DIR or use -d <path>"
      return 1
    fi
    return 0
  fi

  local name="$1"
  local script="$cmd_dir/$name"
  local is_executable=false
  [[ -f "$script" && -x "$script" ]] && is_executable=true

  # Executable script with no filter — run directly (no profile iteration)
  if $is_executable && [[ -z "${2:-}" ]]; then
    shift
    "$script" "$@"
    return
  fi

  # Resolve command text from snippet file or use raw command string
  local command="$name"
  if [[ -f "$script" ]] && ! $is_executable; then
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
