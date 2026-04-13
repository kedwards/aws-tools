#!/usr/bin/env bash

# EC2 helpers
source "$ROOT_DIR/lib/aws/ec2.sh"

# SSM helpers
source "$ROOT_DIR/lib/aws/ssm.sh"

# Shared AWS helpers (now or later)
ensure_aws_cli() {
  command -v aws >/dev/null 2>&1 || {
    log_error "aws CLI not found"
    return 1
  }
}

aws_list_profiles() {
  if [[ ! -f "$HOME/.aws/config" ]]; then
    return 0
  fi

  # Parse [default] and [profile name] sections
  grep -E '^\[(default|profile .+)\]' "$HOME/.aws/config" | while IFS= read -r line; do
    if [[ "$line" =~ ^\[default\]$ ]]; then
      echo "default"
    elif [[ "$line" =~ ^\[profile\ (.+)\]$ ]]; then
      echo "${BASH_REMATCH[1]}"
    fi
  done
}

awst_config_get() {
  local file="$1"
  local section="$2"
  local key="$3"

  [[ ! -f "$file" ]] && return 0

  # Use awk to parse INI file
  awk -F ' *= *' -v section="[$section]" -v key="$key" '
    $0 == section { found=1; next }
    found && $1 == key { print $2; exit }
    found && /^\[.*\]/ { exit }
  ' "$file"
}

choose_profile_and_region() {
  # profile
  if [[ -z "${PROFILE:-}" ]]; then
    PROFILE="${AWS_PROFILE:-}"
  fi

  if [[ -z "$PROFILE" ]]; then
    if [[ "${MENU_NON_INTERACTIVE:-0}" == "1" ]]; then
      log_error "AWS profile required but not set (non-interactive)"
      return 1
    fi

    mapfile -t profiles < <(aws_list_profiles)
    (( ${#profiles[@]} == 0 )) && {
      log_error "No AWS profiles found"
      return 1
    }

    menu_select_one "Select AWS profile" "" PROFILE "${profiles[@]}" || return 130
  fi

  # region: track if explicitly set via -r flag (non-empty before env expansion)
  local region_flag_set=false
  [[ -n "${REGION:-}" ]] && region_flag_set=true

  # Fill from env if not set via flag
  if ! $region_flag_set; then
    REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-}}"
  fi

  # Auto-detect from profile config as a default suggestion
  local detected_region="${REGION:-}"
  if [[ -z "$detected_region" ]]; then
    detected_region="$(
      aws configure get region --profile "$PROFILE" 2>/dev/null ||
      aws configure get sso_region --profile "$PROFILE" 2>/dev/null ||
      true
    )"
  fi

  if ! $region_flag_set; then
    if [[ "${MENU_NON_INTERACTIVE:-0}" == "1" ]]; then
      REGION="$detected_region"
      if [[ -z "$REGION" ]]; then
        log_error "AWS region required but not set (non-interactive)"
        return 1
      fi
    else
      # Always prompt in interactive mode; detected region is listed first
      local all_regions=(
        us-east-1 us-east-2
        us-west-1 us-west-2
        ca-central-1
        eu-west-1 eu-central-1
        ap-southeast-1 ap-northeast-1
      )

      local region_list=()
      if [[ -n "$detected_region" ]]; then
        region_list+=("$detected_region")
        for r in "${all_regions[@]}"; do
          [[ "$r" != "$detected_region" ]] && region_list+=("$r")
        done
      else
        region_list=("${all_regions[@]}")
      fi

      menu_select_one "Select AWS region" "" REGION "${region_list[@]}" || return 130
    fi
  fi

  log_info "Using profile '$PROFILE' in region '$REGION'"

  export AWS_PROFILE="$PROFILE"
  export AWS_REGION="$REGION"
  export AWS_DEFAULT_REGION="$REGION"
  return 0
}

