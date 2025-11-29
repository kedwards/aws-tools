#!/usr/bin/env bash

# Populate global array: INSTANCE_LIST=("Name InstanceId")
aws_get_all_running_instances() {
  local filter_name="${1:-}"
  local jmes='Reservations[].Instances[?State.Name==`running`].{Name:Tags[?Key==`Name`]|[0].Value,Id:InstanceId}[]'

  mapfile -t INSTANCE_LIST < <(
    aws ec2 describe-instances --query "$jmes" --output json |
      jq -r '. | sort_by(.Name)[] | "\(.Name) \(.Id)"' |
      { if [[ -n "$filter_name" ]]; then grep -- "$filter_name" || true; else cat; fi; }
  )
}

# Expand one or more instance identifiers (names or IDs) to running instance IDs
aws_expand_instances() {
  local ids=()
  for ident in "$@"; do
    if [[ "$ident" == i-* ]]; then
      # validate instance is running
      local out
      out=$(aws ec2 describe-instances \
        --instance-ids "$ident" \
        --query "Reservations[].Instances[?State.Name=='running'].InstanceId[]" \
        --output text 2>/dev/null) || true
      if [[ -n "$out" && "$out" != "None" ]]; then
        ids+=("$out")
      else
        log_warn "Instance $ident is not running or not found"
      fi
    else
      local out
      out=$(aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=$ident" "Name=instance-state-name,Values=running" \
        --query "Reservations[].Instances[].InstanceId" \
        --output text 2>/dev/null) || true
      if [[ -n "$out" && "$out" != "None" ]]; then
        # out may contain multiple IDs; split
        read -ra tmp <<<"$out"
        ids+=("${tmp[@]}")
      else
        log_warn "No running instance found with name: $ident"
      fi
    fi
  done

  printf '%s\n' "${ids[@]}"
}
