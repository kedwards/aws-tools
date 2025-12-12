#!/usr/bin/env bash

ssm_exec_usage() {
  cat <<EOF
Usage: ssm exec [OPTIONS]
       aws-ssm-exec [OPTIONS]
       ssmx [OPTIONS]

Run a shell command via AWS SSM on one or more instances.

Options:
  -c <command>      Command to execute on the instances
  -e <environment>  AWS profile (optionally with region as PROFILE:REGION)
  -r <region>       AWS region (overrides region in profile or -e option)
  -i <instances>    Instance names or IDs (semicolon-separated for multiple)
  -h, --help        Show this help message

Examples:
  ssmx -c 'ls -lF; uptime' -e how -i Report                    # single instance
  ssmx -c 'ls -lF; uptime' -e how:us-west-2 -i Report          # with region
  ssmx -c 'ls -lF; uptime' -e how -r us-west-2 -i Report       # region via -r
  ssmx -c 'ls -lF; uptime' -e how -i 'Report;Singleton'        # multiple
  ssmx -c 'ls -lF; uptime' -e how                              # interactive instances
  ssmx -e how                                                  # interactive command + instances
  ssmx -c 'ls -lF; uptime'                                     # interactive profile
  ssmx                                                         # fully interactive

Note: All options are optional and can be combined in any order.
EOF
}

ssm_exec() {
  ensure_aws_cli || return 1

  parse_common_flags "$@" || return 1

  if [[ "$SHOW_HELP" == true ]]; then
    ssm_exec_usage
    return 0
  fi

  # Command: saved or typed
  if [[ -z "$COMMAND_ARG" ]]; then
    if ! aws_ssm_select_command COMMAND_ARG; then
      log_error "No command selected"
      return 1
    fi
    log_info "Selected command: $COMMAND_ARG"
  fi

  # Auto-detect region from AWS config if profile set but region not
  if [[ -z "$REGION" && -n "$PROFILE" && -f "$HOME/.aws/config" ]]; then
    REGION=$(
      aws configure get profile."$PROFILE".region 2>/dev/null ||
      aws configure get profile."$PROFILE".sso_region 2>/dev/null ||
      true
    )
  fi

  # Profile / region selection and validation
  choose_profile_and_region || return 1
  aws_assume_profile "$PROFILE" "$REGION" || return 1

  # Expand instances
  local instance_ids=()

  if [[ -n "$INSTANCES_ARG" ]]; then
    IFS=';' read -ra instance_names <<<"$INSTANCES_ARG"
    local name
    for name in "${instance_names[@]}"; do
      name="$(echo "$name" | xargs)"
      [[ -z "$name" ]] && continue
      mapfile -t expanded_ids < <(aws_expand_instances "$name")
      if [[ ${#expanded_ids[@]} -eq 0 ]]; then
        log_warn "No running instance found matching: $name"
      else
        instance_ids+=("${expanded_ids[@]}")
      fi
    done
  else
    aws_get_all_running_instances ""
    if [[ ${#INSTANCE_LIST[@]} -eq 0 ]]; then
      log_error "No running instances found"
      return 1
    fi

    local selections
    if ! menu_select_multi "Select instances for SSM command" selections "${INSTANCE_LIST[@]}"; then
      return 1
    fi

    if [[ -z "${selections:-}" ]]; then
      log_error "No instances selected"
      return 1
    fi

    local line
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      instance_ids+=("${line##* }")
    done <<<"$selections"
  fi

  if [[ ${#instance_ids[@]} -eq 0 ]]; then
    log_error "No valid instances found"
    return 1
  fi

  log_info "Sending command to ${#instance_ids[@]} instance(s)"

  local tmpfile
  tmpfile=$(mktemp /tmp/ssm-script.XXXXXX)
  trap 'rm -f "${tmpfile:-}"' EXIT

  cat >"$tmpfile" <<EOF
{
  "Parameters": {
    "commands": [
      "#!/bin/bash",
      "$COMMAND_ARG"
    ],
    "executionTimeout": ["600"]
  }
}
EOF

  local cmd_id
  cmd_id=$(aws ssm send-command \
    --instance-ids "${instance_ids[@]}" \
    --document-name "AWS-RunShellScript" \
    --cli-input-json "file://$tmpfile" \
    --query 'Command.CommandId' \
    --output text)

  echo "Command launched with id: $cmd_id"
  local n_instances="${#instance_ids[@]}"

  while true; do
    local finished=0
    local inst
    for inst in "${instance_ids[@]}"; do
      local status
      status=$(aws ssm get-command-invocation \
        --command-id "$cmd_id" \
        --instance-id "$inst" \
        --query Status \
        --output text 2>/dev/null | tr 'A-Z' 'a-z')
      local now
      now=$(date +%Y-%m-%dT%H:%M:%S%z)
      echo "$now $inst: $status"
      case "$status" in
        pending|inprogress|delayed) : ;;
        *) finished=$((finished+1)) ;;
      esac
    done
    [[ $finished -ge $n_instances ]] && break
    sleep 2
  done

  for inst in "${instance_ids[@]}"; do
    local status out err
    status=$(aws ssm get-command-invocation \
      --command-id "$cmd_id" \
      --instance-id "$inst" \
      --query Status --output text) || true
    out=$(aws ssm get-command-invocation \
      --command-id "$cmd_id" \
      --instance-id "$inst" \
      --query StandardOutputContent --output text) || true
    err=$(aws ssm get-command-invocation \
      --command-id "$cmd_id" \
      --instance-id "$inst" \
      --query StandardErrorContent --output text) || true

    echo "------------------------------------"
    echo "RESULTS FROM $inst (STATUS $status):"
    [[ -n "$out" ]] && {
      echo "STDOUT:"
      echo "$out"
      echo "------------------------------------"
    }
    [[ -n "$err" ]] && {
      echo "STDERR:"
      echo "$err"
      echo "------------------------------------"
    }
    if [[ -z "$out" && -z "$err" ]]; then
      echo "NO OUTPUT RETURNED"
    fi
  done

  return 0
}
