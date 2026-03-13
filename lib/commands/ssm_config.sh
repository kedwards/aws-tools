#!/usr/bin/env bash

ssm_config_usage() {
  cat <<EOF
Usage: ssm config

Display current aws-ssm-tools configuration including file paths,
directories, and environment variables.
EOF
}

ssm_config() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    ssm_config_usage
    return 0
  fi

  local install_dir="$HOME/.local/share/aws-ssm-tools"
  local config_dir="$HOME/.config/aws-ssm-tools"
  local cache_dir="$HOME/.cache/ssm"
  local bin_dir="$HOME/.local/bin"

  echo "aws-ssm-tools v${VERSION:-unknown}"
  echo ""

  # ── Installation ──
  echo "Installation"
  _config_path "  Install dir" "$install_dir"
  _config_path "  Binary dir" "$bin_dir"
  _config_path "  User config dir" "$config_dir"
  _config_path "  Cache dir" "$cache_dir"
  echo ""

  # ── Connection configs ──
  echo "Connection Configs"
  _config_path "  Default" "$install_dir/connections.config"
  _config_path "  User" "$config_dir/connections.user.config"
  echo ""

  # ── Commands directories ──
  echo "SSM Commands (ssm exec)"
  _config_path "  Installed" "$install_dir/commands/ssm"
  _config_path "  User" "$config_dir/commands/ssm"
  _config_var  "  Custom dir" "AWS_SSM_COMMAND_DIR"
  echo ""

  echo "AWS Commands (ssm run)"
  _config_path "  Installed" "$install_dir/commands/aws"
  _config_path "  User" "$config_dir/commands/aws"
  _config_var  "  Custom dir" "AWS_TOOLS_CMD_DIR"
  echo ""

  # ── AWS ──
  echo "AWS"
  _config_path "  Config file" "$HOME/.aws/config"
  _config_show "  Profile" "${AWS_PROFILE:-}" "(not set)"
  _config_show "  Region" "${AWS_REGION:-${AWS_DEFAULT_REGION:-}}" "(not set)"
  echo ""

  # ── Environment variables ──
  echo "Environment Variables"
  echo "  Logging:"
  _config_var "    AWS_LOG_LEVEL" "AWS_LOG_LEVEL" "INFO"
  _config_var "    AWS_LOG_COLOR" "AWS_LOG_COLOR" "1"
  _config_var "    AWS_LOG_TIMESTAMP" "AWS_LOG_TIMESTAMP" "1"
  _config_var "    AWS_LOG_FILE" "AWS_LOG_FILE" "(disabled)"
  _config_var "    AWS_LOG_FILE_MAX_SIZE" "AWS_LOG_FILE_MAX_SIZE" "1048576"
  _config_var "    AWS_LOG_FILE_ROTATE" "AWS_LOG_FILE_ROTATE" "5"
  echo "  Auth:"
  _config_var "    AWS_AUTH_AUTO_LOGIN" "AWS_AUTH_AUTO_LOGIN" "0"
  echo "  Menu:"
  _config_var "    MENU_NO_FZF" "MENU_NO_FZF" "0"
  _config_var "    MENU_NON_INTERACTIVE" "MENU_NON_INTERACTIVE" "0"
  _config_var "    MENU_ASSUME_FIRST" "MENU_ASSUME_FIRST" "0"
  echo "  Cache:"
  _config_var "    SSM_CACHE_TTL" "SSM_CACHE_TTL" "30"

  # ── Dependencies ──
  echo ""
  echo "Dependencies"
  _config_dep "  aws" "required"
  _config_dep "  assume" "required"
  _config_dep "  rsync" "required"
  _config_dep "  fzf" "optional"
  _config_dep "  shellcheck" "optional"
}

# ── Helpers ──

# Print a path with exists/missing indicator
_config_path() {
  local label="$1" path="$2"
  if [[ -e "$path" ]]; then
    printf "%-28s %s\n" "$label" "$path"
  else
    printf "%-28s %s (missing)\n" "$label" "$path"
  fi
}

# Print an env var's current value (or default)
_config_var() {
  local label="$1" var_name="$2" default="${3:-}"
  local value="${!var_name:-}"
  if [[ -n "$value" ]]; then
    printf "%-28s %s\n" "$label" "$value"
  else
    printf "%-28s %s\n" "$label" "${default:-(not set)}"
  fi
}

# Print a value with fallback
_config_show() {
  local label="$1" value="$2" fallback="$3"
  printf "%-28s %s\n" "$label" "${value:-$fallback}"
}

# Print dependency status
_config_dep() {
  local label="$1" note="$2"
  local cmd="${label##* }"
  if command -v "$cmd" >/dev/null 2>&1; then
    local ver
    ver=$("$cmd" --version 2>&1 | head -n1) || ver="found"
    printf "%-28s ✓ %s\n" "$label" "$ver"
  else
    printf "%-28s ✗ not found (%s)\n" "$label" "$note"
  fi
}
