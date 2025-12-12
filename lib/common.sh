#!/usr/bin/env bash
# common.sh — Shared helpers for AWS SSM CLI

# ------------------------------
# REGION LIST (extend as needed)
# ------------------------------
AWS_REGIONS=("us-east-1" "us-west-2" "us-west-1" "us-east-2" "ca-central-1")

# ------------------------------
# ENSURE AWS CLI EXISTS
# ------------------------------
ensure_aws_cli() {
  if ! command -v aws >/dev/null 2>&1; then
    log_error "AWS CLI not found in PATH"
    return 1
  fi
}

# ------------------------------
# GENERIC INPUT PROMPT
# ------------------------------
ensure_value() {
  local varname="$1"
  local prompt="$2"
  local current="${!varname}"

  if [[ -z "$current" ]]; then
    read -rp "$prompt: " input
    printf -v "$varname" "%s" "$input"
  fi
}

# ================================================================
#  SSO AUTO-VALIDATION / AUTO-LOGIN LOGIC
# ================================================================
aws_sso_validate_or_login() {
  log_debug "Validating SSO session for profile '$PROFILE' region '$REGION'"

  # Try a harmless call to validate authentication
  if aws sts get-caller-identity --profile "$PROFILE" --region "$REGION" >/dev/null 2>&1; then
    log_debug "SSO token for '$PROFILE' is valid."
    return 0
  fi

  log_warn "SSO token missing or expired for profile '$PROFILE'"
  log_info "Attempting login via assume wrapper: assumego $PROFILE -r $REGION"

  # Try your assume function
  if declare -f assumego >/dev/null 2>&1; then
    if assumego "$PROFILE" -r "$REGION"; then
      log_success "SSO refreshed using assume wrapper."
      return 0
    fi
  fi

  log_warn "Assume wrapper did not refresh credentials."
  log_info "Trying native AWS SSO login: aws sso login --profile $PROFILE"

  if aws sso login --profile "$PROFILE"; then
    log_success "SSO session refreshed using AWS SSO login."
    return 0
  fi

  log_error "Failed to authenticate profile '$PROFILE'."
  echo "Manually run:"
  echo "  aws sso login --profile $PROFILE"
  return 1
}

# ================================================================
#  GRANTED ASSUME PROFILE (for traditional bin commands)
# ================================================================
aws_assume_profile() {
  local profile="$1"
  local region="$2"

  log_info "Assuming AWS profile '$profile' in region '$region'"

  export AWS_PROFILE="$profile"
  export AWS_REGION="$region"

  # Capture Granted credentials
  local cred_line
  cred_line=$(assumego "$profile" -r "$region" 2>/dev/null | sed -n 's/^GrantedAssume //p')

  if [[ -z "$cred_line" ]]; then
    log_error "Failed to obtain credentials from assumego"
    return 1
  fi

  # cred_line format:
  # AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_PROFILE AWS_SESSION_EXPIRATION
  read -r AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_PROFILE AWS_SESSION_EXPIRATION <<< "$cred_line"

  export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_SESSION_EXPIRATION AWS_PROFILE

  log_debug "Exported Granted session credentials:"
  log_debug "AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID:0:4}****"
  log_debug "AWS_SESSION_TOKEN=${AWS_SESSION_TOKEN:0:10}****"
}

# ================================================================
#  PROFILE + REGION SELECTION LOGIC
# ================================================================
aws_list_profiles() {
  if [[ -f "$HOME/.aws/config" ]]; then
    grep '^\[profile ' "$HOME/.aws/config" |
      awk '{ print substr($2,1,length($2)-1) }'
  else
    log_warn "No ~/.aws/config found"
  fi
}

choose_profile_and_region() {
  # Allow AWS_PROFILE to override CLI
  if [[ -z "$PROFILE" && -n "${AWS_PROFILE:-}" ]]; then
    PROFILE="$AWS_PROFILE"
  fi

  # Step 1 — Choose PROFILE if not provided
  if [[ -z "$PROFILE" ]]; then
    local profiles; profiles=$(aws_list_profiles)
    mapfile -t all_profiles <<<"$profiles"

    if [[ ${#all_profiles[@]} -eq 0 ]]; then
      log_error "No AWS profiles found"
      return 1
    fi

    menu_select_one "Select AWS profile" "" PROFILE "${all_profiles[@]}" || return 1
  fi

  # Step 2 — Detect REGION from AWS config using AWS CLI, not greps
  if [[ -z "$REGION" ]]; then
    REGION=$(
      aws configure get profile."$PROFILE".region ||
      aws configure get profile."$PROFILE".sso_region ||
      true
    )
  fi

  # Step 3 — Prompt for region if still unknown
  if [[ -z "$REGION" ]]; then
    menu_select_one "Select region for $PROFILE" "" REGION "${AWS_REGIONS[@]}" || return 1
  fi

  log_info "Using profile '$PROFILE' in region '$REGION'"

  # Step 4 — Validate or refresh SSO session BEFORE any AWS calls
  aws_sso_validate_or_login || return 1
}

# ================================================================
#  CONFIG FILE PARSER (INI-STYLE)
# ================================================================
aws_ssm_config_get() {
  local file="$1" section="$2" key="$3"
  awk -F ' *= *' -v s="[$section]" -v k="$key" '
    $0 == s {found=1; next}
    found && $1==k {print $2; exit}
    found && /^\[.*\]/ {exit}
  ' "$file"
}

# ================================================================
#  INSTANCE EXPANSION HELPERS
# ================================================================
aws_expand_instances() {
  local name="$1"

  # Direct instance-id
  if [[ "$name" == i-* ]]; then
    echo "$name"
    return 0
  fi

  log_debug "Expanding instance name '$name' via EC2 describe-instances"

  aws ec2 describe-instances \
    --filters "Name=instance-state-name,Values=running" "Name=tag:Name,Values=$name" \
    --query 'Reservations[].Instances[].InstanceId' \
    --output text 2>/dev/null | tr '\t' '\n'
}

aws_get_all_running_instances() {
  INSTANCE_LIST=()

  log_debug "Fetching running EC2 instances for profile '$PROFILE' region '$REGION'"

  local output
  if ! output=$(aws ec2 describe-instances \
      --filters "Name=instance-state-name,Values=running" \
      --output json 2>/dev/null); then
    log_error "Failed to fetch instance list"
    return 1
  fi

  local jq_query='Reservations[].Instances[] |
                   {id: InstanceId,
                    name: (Tags[]? | select(.Key=="Name") | .Value // "unknown")} |
                   "\(.name) \(.id)"'

  mapfile -t INSTANCE_LIST < <(jq -r "$jq_query" <<<"$output" 2>/dev/null || true)

  log_debug "Found ${#INSTANCE_LIST[@]} running instances"
}

# ================================================================
#  SAVED COMMANDS (for ssm exec)
# ================================================================
aws_ssm_load_commands() {
  local default_config="$HOME/.local/share/aws-ssm-tools/commands.config"
  local user_config="$HOME/.config/aws-ssm-tools/commands.user.config"
  local custom_config="${AWS_SSM_COMMAND_FILE:-}"

  # Alternative location (next to ssm binary)
  if [[ ! -f "$default_config" ]]; then
    local script_dir; script_dir="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local alt="${script_dir}/../commands.config"
    [[ -f "$alt" ]] && default_config="$alt"
  fi

  COMMAND_NAMES=()
  COMMAND_DESCRIPTIONS=()
  COMMAND_STRINGS=()

  load_from_file() {
    local file="$1"
    [[ ! -f "$file" ]] && return 0

    while IFS='|' read -r name desc cmd; do
      [[ -z "$name" ]] && continue
      [[ "$name" =~ ^# ]] && continue

      local i found=false
      for i in "${!COMMAND_NAMES[@]}"; do
        if [[ "${COMMAND_NAMES[$i]}" == "$name" ]]; then
          COMMAND_DESCRIPTIONS[$i]="$desc"
          COMMAND_STRINGS[$i]="$cmd"
          found=true
          break
        fi
      done

      if [[ "$found" == false ]]; then
        COMMAND_NAMES+=("$name")
        COMMAND_DESCRIPTIONS+=("$desc")
        COMMAND_STRINGS+=("$cmd")
      fi
    done < "$file"
  }

  load_from_file "$default_config"
  load_from_file "$user_config"
  [[ -n "$custom_config" && -f "$custom_config" ]] && load_from_file "$custom_config"

  (( ${#COMMAND_NAMES[@]} > 0 ))
}

aws_ssm_select_command() {
  local __result_var="$1"

  if ! aws_ssm_load_commands; then
    log_warn "No saved commands found — falling back to manual entry."
    return 1
  fi

  local display=()
  local i
  for i in "${!COMMAND_NAMES[@]}"; do
    display+=("${COMMAND_NAMES[$i]}: ${COMMAND_DESCRIPTIONS[$i]}")
  done

  local selected
  if ! menu_select_one "Select saved command" "Saved Commands" selected "${display[@]}"; then
    return 1
  fi

  local selected_name="${selected%%:*}"

  for i in "${!COMMAND_NAMES[@]}"; do
    if [[ "${COMMAND_NAMES[$i]}" == "$selected_name" ]]; then
      local cmd="${COMMAND_STRINGS[$i]}"
      cmd=$(eval "echo \"$cmd\"")  # expand variables
      printf -v "$__result_var" '%s' "$cmd"
      return 0
    fi
  done

  log_error "Command '$selected_name' not found in list"
  return 1
}
