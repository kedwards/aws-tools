#!/usr/bin/env bash
# Logging utilities with log levels, colors, timestamps

: "${AWS_LOG_LEVEL:=INFO}"   # DEBUG, INFO, WARN, ERROR
: "${AWS_LOG_TIMESTAMP:=1}"  # 1 = show timestamps, 0 = no timestamps
: "${AWS_LOG_COLOR:=auto}"   # auto, on, off

# -------- Colors --------
_color_enabled() {
  case "$AWS_LOG_COLOR" in
    on) return 0 ;;
    off) return 1 ;;
    auto)
      [[ -t 2 ]] && return 0
      return 1
      ;;
  esac
}

if _color_enabled; then
  C_RED='\033[0;31m'
  C_GREEN='\033[0;32m'
  C_YELLOW='\033[0;33m'
  C_BLUE='\033[0;34m'
  C_DIM='\033[2m'
  C_RESET='\033[0m'
else
  C_RED=""
  C_GREEN=""
  C_YELLOW=""
  C_BLUE=""
  C_DIM=""
  C_RESET=""
fi

# -------- Level Mapping --------
_log_level_num() {
  case "${1:-INFO}" in
    DEBUG) echo 10 ;;
    INFO)  echo 20 ;;
    SUCCESS) echo 25 ;;
    WARN)  echo 30 ;;
    ERROR) echo 40 ;;
    FATAL) echo 50 ;;
    *) echo 20 ;;
  esac
}

_log_should_log() {
  local msg_level="$1"
  local current="${AWS_LOG_LEVEL}"
  [[ $(_log_level_num "$msg_level") -ge $(_log_level_num "$current") ]]
}

_log_prefix() {
  local level="$1"
  local color="$2"

  local ts=""
  if [[ "$AWS_LOG_TIMESTAMP" == "1" ]]; then
    ts="[$(date '+%Y-%m-%d %H:%M:%S')] "
  fi

  printf "%b%s[%s]%b " \
    "$color" \
    "$ts" \
    "$level" \
    "$C_RESET"
}

# --------- Log Functions ----------
log_debug()   { _log_should_log DEBUG   && echo "$(_log_prefix DEBUG "$C_DIM")$*" >&2; }
log_info()    { _log_should_log INFO    && echo "$(_log_prefix INFO "$C_BLUE")$*" >&2; }
log_success() { _log_should_log SUCCESS && echo "$(_log_prefix SUCCESS "$C_GREEN")$*" >&2; }
log_warn()    { _log_should_log WARN    && echo "$(_log_prefix WARN "$C_YELLOW")$*" >&2; }
log_error()   { _log_should_log ERROR   && echo "$(_log_prefix ERROR "$C_RED")$*" >&2; }

log_fatal() {
  echo "$(_log_prefix FATAL "$C_RED")$*" >&2
  exit 1
}
