#!/usr/bin/env bash

ssm_connect_usage() {
  cat <<EOF
Usage: ssm connect [OPTIONS]

Connect to an instance via AWS SSM.

Options:
  -p, --profile PROFILE          AWS profile to use
  -r, --region  REGION           AWS region to use
  -i, --instance INSTANCE        Instance name or ID (optional)
  -c, --config                   Use config file based port-forwarding mode
  -f, --file CONFIG_FILE         Override config file path
  -h, --help                     Show this help

Config mode expects an INI file (default: \$SSMF_CONF or ~/.ssmf.cfg) like:

  [db-conn]
  port = 5432
  local_port = 5432
  host = localhost
  url = http://localhost:5432/
  profile = db-profile
  region = us-west-2
  name = instance-tagname (optional)
EOF
}

ssm_connect() {
  ensure_aws_cli || return 1

  parse_common_flags "$@" || return 1

  if [[ "$SHOW_HELP" == true ]]; then
    ssm_connect_usage
    return 0
  fi

  # Config based PORT-FORWARD mode
  if $CONFIG_MODE; then
    local CONFIG_FILE_PATH
    CONFIG_FILE_PATH="${CONFIG_FILE:-${SSMF_CONF:-$HOME/.ssmf.cfg}}"

    if [[ ! -f "$CONFIG_FILE_PATH" ]]; then
      log_error "Config file not found: $CONFIG_FILE_PATH"
      return 1
    fi

    mapfile -t connections < <(grep -oP '(?<=^\[).*?(?=\])' "$CONFIG_FILE_PATH")
    if [[ ${#connections[@]} -eq 0 ]]; then
      log_error "No [sections] found in $CONFIG_FILE_PATH"
      return 1
    fi

    local connection
    if ! menu_select_one "Select connection" "" connection "${connections[@]}"; then
      return 1
    fi

    PROFILE=$(aws_ssm_config_get "$CONFIG_FILE_PATH" "$connection" "profile")
    REGION=$(aws_ssm_config_get "$CONFIG_FILE_PATH" "$connection" "region")
    local port local_port host url name

    port=$(aws_ssm_config_get "$CONFIG_FILE_PATH" "$connection" "port")
    local_port=$(aws_ssm_config_get "$CONFIG_FILE_PATH" "$connection" "local_port")
    host=$(aws_ssm_config_get "$CONFIG_FILE_PATH" "$connection" "host")
    url=$(aws_ssm_config_get "$CONFIG_FILE_PATH" "$connection" "url")
    name=$(aws_ssm_config_get "$CONFIG_FILE_PATH" "$connection" "name")

    if [[ -z "$PROFILE" || -z "$REGION" || -z "$port" ]]; then
      log_error "Invalid config for [$connection] - require profile, region, port"
      return 1
    fi

    local_port="${local_port:-$port}"
    host="${host:-localhost}"

    choose_profile_and_region || return 1
    aws_sso_validate_or_login || return 1

    local instance_id instance_name
    if [[ -n "$name" ]]; then
      instance_name="$name"
      instance_id=$(aws_expand_instances "$name" | head -n1)
      if [[ -z "$instance_id" ]]; then
        log_error "No running instance found with name: $name"
        return 1
      fi
    else
      aws_get_all_running_instances ""
      if [[ ${#INSTANCE_LIST[@]} -eq 0 ]]; then
        log_error "No running instances found"
        return 1
      fi
      local chosen
      if ! menu_select_one "Select instance for port forwarding" "" chosen "${INSTANCE_LIST[@]}"; then
        return 1
      fi
      instance_name="${chosen% *}"
      instance_id="${chosen##* }"
    fi

    log_info "Starting SSM port forwarding: ${instance_name} (${instance_id}) -> ${host}:${port} (local:${local_port})"
    aws ssm start-session \
      --target "$instance_id" \
      --document-name AWS-StartPortForwardingSessionToRemoteHost \
      --parameters "{\"host\":[\"$host\"],\"portNumber\":[\"$port\"],\"localPortNumber\":[\"$local_port\"]}" &

    local ssm_pid=$!
    log_info "SSM port-forward session PID: $ssm_pid"

    if [[ -n "$url" ]]; then
      sleep 2
      xdg-open "$url" 2>/dev/null || log_warn "Failed to open URL: $url"
    fi
    return 0
  fi

  # Shell mode (Default)
  local target="$INSTANCES_ARG"
  if [[ -z "$target" && ${#POSITIONAL[@]} -gt 0 ]]; then
    target="${POSITIONAL[0]}"
  fi

  # Choose / assume profile & region
  choose_profile_and_region || return 1
  aws_assume_profile "$PROFILE" "$REGION" || return 1

  local instance_id instance_name

  if [[ -z "$target" ]]; then
    aws_get_all_running_instances ""
    if [[ ${#INSTANCE_LIST[@]} -eq 0 ]]; then
      log_error "No running instances found"
      return 1
    fi
    local chosen
    if ! menu_select_one "Select instance to connect to" "" chosen "${INSTANCE_LIST[@]}"; then
      return 1
    fi
    instance_name="${chosen% *}"
    instance_id="${chosen##* }"
  elif [[ "$target" == i-* ]]; then
    instance_id="$target"
    instance_name="$target"
  else
    instance_id=$(aws_expand_instances "$target" | head -n1)
    instance_name="$target"
    if [[ -z "$instance_id" ]]; then
      log_error "No running instance found with name: $target"
      return 1
    fi
  fi

  log_info "Starting SSM session to $instance_name ($instance_id)"
  aws ssm start-session --target "$instance_id"
}
