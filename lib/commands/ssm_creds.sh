#!/usr/bin/env bash

ssm_creds_usage() {
  cat <<EOF
Usage: ssm creds <store|use>

Manage AWS credentials for the current shell.

Subcommands:
  store <env>  Export AWS credentials for <env> into the current shell
  use          Re-apply stored credentials (AK/SK/ST) as AWS_ env vars

Examples:
  eval "\$(ssm creds store myenv)"
  eval "\$(ssm creds use)"
EOF
}

ssm_creds_store() {
  local env="${1:-}"

  if [[ -z "$env" || "$env" == "-h" || "$env" == "--help" ]]; then
    cat <<EOF
Usage: ssm creds store <env>
  Exports AWS credentials for <env> into the current shell.
  Requires: assume (Granted)

Examples:
  eval "\$(ssm creds store myenv)"
EOF
    return 0
  fi

  if ! command -v assume >/dev/null 2>&1; then
    log_error "'assume' (Granted) not found in PATH"
    return 1
  fi

  if [[ "${AWS_AUTH_DISABLE_ASSUME:-0}" == "1" ]]; then
    log_debug "Skipping assume (AWS_AUTH_DISABLE_ASSUME=1)"
    return 0
  fi

  local creds
  creds="$(assume "$env" --exec env | awk -F= '
    /^AWS_ACCESS_KEY_ID=/ ||
    /^AWS_SECRET_ACCESS_KEY=/ ||
    /^AWS_SESSION_TOKEN=/ ||
    /^AWS_REGION=/ {
      print "export " $1 "=\"" $2 "\""
    }
  ')"

  # Eval into current (sub)shell so vars are available for substitution below
  eval "$creds"

  cat <<EOF
$creds
export AK="$AWS_ACCESS_KEY_ID"
export SK="$AWS_SECRET_ACCESS_KEY"
export ST="$AWS_SESSION_TOKEN"
EOF
}

ssm_creds_use() {
  printf 'export AWS_ACCESS_KEY_ID="%s" AWS_SECRET_ACCESS_KEY="%s" AWS_SESSION_TOKEN="%s"\n' \
    "${AK:-}" "${SK:-}" "${ST:-}"
}

ssm_creds() {
  local subcmd="${1:-}"

  case "$subcmd" in
    store) shift; ssm_creds_store "$@" ;;
    use)   ssm_creds_use ;;
    *)     ssm_creds_usage ;;
  esac
}
