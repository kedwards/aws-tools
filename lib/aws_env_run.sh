#!/usr/bin/env bash

aws_env_run_usage() {
  cat <<EOF
Usage:
  aws-env-run '<command>' [profile:region profile:region ...]
  aws-env-run '<command>'             # interactive profile/region selection

Placeholders in command:
  #ENV    will be replaced with the active AWS profile
  #REGION will be replaced with the active AWS region
EOF
}

aws_env_run_main() {
  if [[ "$#" -lt 1 ]]; then
    aws_env_run_usage
    return 1
  fi

  local command="$1"
  shift
  local pairs=("$@")

  if [[ ${#pairs[@]} -eq 0 ]]; then
    # interactive selection
    local profiles
    profiles=$(aws_list_profiles)
    read -ra all_profiles <<<"$profiles"

    if [[ ${#all_profiles[@]} -eq 0 ]]; then
      log_error "No AWS profiles found"
      return 1
    fi

    local selected_profiles
    if ! menu_select_multi "Select profiles" selected_profiles "${all_profiles[@]}"; then
      return 1
    fi

    local regions=("us-east-1" "us-east-2" "us-west-1" "us-west-2" "ca-central-1" "eu-west-1" "eu-central-1" "ap-southeast-1" "ap-southeast-2" "ap-northeast-1")
    pairs=()

    while IFS= read -r prof; do
      [[ -z "$prof" ]] && continue
      local sel_regions
      if ! menu_select_multi "Select region(s) for $prof" sel_regions "${regions[@]}"; then
        sel_regions="us-east-1"
      fi
      while IFS= read -r r; do
        [[ -z "$r" ]] && continue
        pairs+=("${prof}:${r}")
      done <<<"$sel_regions"
    done <<<"$selected_profiles"
  fi

  for pair in "${pairs[@]}"; do
    [[ -z "$pair" ]] && continue
    local env region
    env="${pair%%:*}"
    region="${pair##*:}"
    [[ -z "$region" || "$region" == "$env" ]] && region="us-east-1"

    log_info "Running against $env ($region)"
    aws_profile_switch "$env" -r "$region"

    local cmd_to_run
    cmd_to_run="${command//#ENV/$AWS_PROFILE}"
    cmd_to_run="${cmd_to_run//#REGION/$AWS_REGION}"

    log_debug "Executing: $cmd_to_run"
    bash -c "$cmd_to_run"
  done
}
