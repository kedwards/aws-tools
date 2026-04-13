#!/usr/bin/env bash

AWST_CREDS_DIR="${AWST_CREDS_DIR:-$HOME/.local/share/aws-tools/creds}"

awst_creds_usage() {
  cat <<EOF
Usage: awst creds <store|use|list|clear> [profile]

Manage AWS credentials per profile.

Subcommands:
  store <profile>   Assume <profile> and persist credentials to disk
  use [profile]     Export stored credentials for <profile> into the shell
  list              List stored credential profiles
  clear [profile]   Remove stored credentials (all profiles if none given)

Examples:
  eval "\$(awst creds store dev)"
  eval "\$(awst creds use dev)"
  awst creds list
  awst creds clear dev
EOF
}

awst_creds_store() {
  local profile="${1:-}"

  if [[ -z "$profile" || "$profile" == "-h" || "$profile" == "--help" ]]; then
    cat <<EOF
Usage: awst creds store <profile>
  Assumes <profile> via Granted and persists credentials to disk.
  Requires: assume (Granted)

Examples:
  eval "\$(awst creds store dev)"
  eval "\$(awst creds use dev)"
EOF
    return 0
  fi

  if ! command -v assume >/dev/null 2>&1; then
    log_error "'assume' (Granted) not found in PATH"
    log_error "Install: https://docs.commonfate.io/granted/getting-started"
    return 1
  fi

  if [[ "${AWST_AUTH_DISABLE_ASSUME:-0}" == "1" ]]; then
    log_debug "Skipping assume (AWST_AUTH_DISABLE_ASSUME=1)"
    return 0
  fi

  # Run assume once and capture raw env output
  local raw_env
  if ! raw_env="$(assume "$profile" --exec env 2>/dev/null)"; then
    log_error "Failed to assume profile '$profile'"
    return 1
  fi

  # Extract credential vars (preserving full values including '=' in base64 tokens)
  local raw_creds
  raw_creds="$(echo "$raw_env" | awk '
    /^(AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY|AWS_SESSION_TOKEN|AWS_REGION)=/ {
      eq = index($0, "=")
      key = substr($0, 1, eq - 1)
      val = substr($0, eq + 1)
      print key "=" val
    }
  ')"

  if [[ -z "$raw_creds" ]]; then
    log_error "No AWS credentials returned by assume for profile '$profile'"
    return 1
  fi

  # Persist to per-profile file
  mkdir -p "$AWST_CREDS_DIR"
  chmod 700 "$AWST_CREDS_DIR"
  local creds_file="$AWST_CREDS_DIR/${profile}.env"
  printf '%s\n' "$raw_creds" > "$creds_file"
  chmod 600 "$creds_file"
  log_debug "Credentials stored to $creds_file"

  # Output export statements for eval and capture shorthand vars
  local ak="" sk="" st=""
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    local key="${line%%=*}"
    local val="${line#*=}"
    printf 'export %s="%s"\n' "$key" "$val"
    case "$key" in
      AWS_ACCESS_KEY_ID)     ak="$val" ;;
      AWS_SECRET_ACCESS_KEY) sk="$val" ;;
      AWS_SESSION_TOKEN)     st="$val" ;;
    esac
  done <<< "$raw_creds"

  # Export AWS_PROFILE for SSO-aware tooling
  printf 'export AWS_PROFILE="%s"\n' "$profile"

  # Backwards-compat shorthand vars
  printf 'export AK="%s"\n' "$ak"
  printf 'export SK="%s"\n' "$sk"
  printf 'export ST="%s"\n' "$st"
}

awst_creds_use() {
  local profile="${1:-}"

  # No profile: backwards-compat — re-apply AK/SK/ST shorthand vars
  if [[ -z "$profile" ]]; then
    printf 'export AWS_ACCESS_KEY_ID="%s" AWS_SECRET_ACCESS_KEY="%s" AWS_SESSION_TOKEN="%s"\n' \
      "${AK:-}" "${SK:-}" "${ST:-}"
    return 0
  fi

  local creds_file="$AWST_CREDS_DIR/${profile}.env"

  if [[ ! -f "$creds_file" ]]; then
    log_error "No stored credentials for profile '$profile'"
    log_error "Run: eval \"\$(awst creds store $profile)\""
    return 1
  fi

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    local key="${line%%=*}"
    local val="${line#*=}"
    printf 'export %s="%s"\n' "$key" "$val"
  done < "$creds_file"

  printf 'export AWS_PROFILE="%s"\n' "$profile"
}

awst_creds_list() {
  if [[ ! -d "$AWST_CREDS_DIR" ]]; then
    echo "No stored credentials found"
    return 0
  fi

  local found=false
  local now
  now="$(date +%s)"

  for f in "$AWST_CREDS_DIR"/*.env; do
    [[ -f "$f" ]] || continue
    local name
    name="$(basename "$f" .env)"
    local mtime age age_str
    mtime="$(stat -c %Y "$f" 2>/dev/null || echo 0)"
    age=$(( now - mtime ))
    if (( age < 3600 )); then
      age_str="$(( age / 60 ))m ago"
    elif (( age < 86400 )); then
      age_str="$(( age / 3600 ))h ago"
    else
      age_str="$(( age / 86400 ))d ago"
    fi
    printf "  %-30s (stored %s)\n" "$name" "$age_str"
    found=true
  done

  if ! $found; then
    echo "No stored credentials found"
  fi
}

awst_creds_clear() {
  local profile="${1:-}"

  if [[ ! -d "$AWST_CREDS_DIR" ]]; then
    log_info "No stored credentials found"
    return 0
  fi

  if [[ -n "$profile" ]]; then
    local creds_file="$AWST_CREDS_DIR/${profile}.env"
    if [[ ! -f "$creds_file" ]]; then
      log_error "No stored credentials for profile '$profile'"
      return 1
    fi
    rm -f "$creds_file"
    log_info "Cleared credentials for profile '$profile'"
  else
    rm -f "$AWST_CREDS_DIR"/*.env 2>/dev/null || true
    log_info "Cleared all stored credentials"
  fi
}

awst_creds() {
  local subcmd="${1:-}"

  case "$subcmd" in
    store) shift; awst_creds_store "$@" ;;
    use)   shift; awst_creds_use "$@" ;;
    list)  awst_creds_list ;;
    clear) shift; awst_creds_clear "$@" ;;
    -h|--help) awst_creds_usage ;;
    *)     awst_creds_usage ;;
  esac
}
