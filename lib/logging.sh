#!/usr/bin/env bash
# Simple logging utilities with log levels

: "${AWS_LOG_LEVEL:=INFO}" # DEBUG, INFO, WARN, ERROR

_log_level_num() {
  case "${1:-INFO}" in
  DEBUG) echo 10 ;;
  INFO) echo 20 ;;
  WARN) echo 30 ;;
  ERROR) echo 40 ;;
  *) echo 20 ;;
  esac
}

_log_should_log() {
  local msg_level="$1"
  local current_level="${AWS_LOG_LEVEL}"
  [[ $(_log_level_num "$msg_level") -ge $(_log_level_num "$current_level") ]]
}

log_debug() {
  _log_should_log DEBUG && echo "[DEBUG] $*" >&2
}

log_info() {
  _log_should_log INFO && echo "[INFO] $*" >&2
}

log_warn() {
  _log_should_log WARN && echo "[WARN]  $*" >&2
}

log_error() {
  _log_should_log ERROR && echo "[ERROR] $*" >&2
}
