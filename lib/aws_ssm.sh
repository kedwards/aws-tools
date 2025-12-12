#!/usr/bin/env bash

# Common list of AWS regions
AWS_REGIONS=("us-east-1" "us-west-2")

aws_ssm_config_get() {
  local file="$1" section="$2" key="$3"
  awk -F ' *= *' -v s="[$section]" -v k="$key" '
    $0 == s {found=1; next}
    found && $1==k {print $2; exit}
    found && /^\[.*\]/ {exit}
  ' "$file"
}

aws_list_profiles() {
  if [[ -f "$HOME/.aws/config" ]]; then
    grep '^\[profile ' "$HOME/.aws/config" |
      awk '{ print substr($2,1,length($2)-1) }'
  else
    log_warn "No ~/.aws/config found"
  fi
}

aws_ssm_connect_usage() {
  cat <<EOF
Usage:
  aws-ssm-connect [INSTANCE_NAME|INSTANCE_ID]
  aws-ssm-connect --config

Connect to an instance via AWS SSM. With --config, uses ~/.ssmf.cfg or \$SSMF_CONF:

  [db-conn]
  port = 5432
  local_port = 5432
  host = localhost
  url = http://localhost:5432/
  profile = db-profile
  region = us-west-2
  name = instance-tagname (optional)

If 'name' is omitted, you will be prompted to choose a running instance.
EOF
}

aws_ssm_connect_main() {
  local use_config=false
  local arg="${1:-}"

  case "$arg" in
  -h | --help)
    aws_ssm_connect_usage
    return 0
    ;;
  -c | --config)
    use_config=true
    shift || true
    ;;
  esac

  if ! command -v aws >/dev/null 2>&1; then
    log_error "AWS CLI not found"
    return 1
  fi

  if $use_config; then
    local CONFIG_FILE="${SSMF_CONF:-$HOME/.ssmf.cfg}"
    if [[ ! -f "$CONFIG_FILE" ]]; then
      log_error "Config file not found: $CONFIG_FILE"
      echo "Create it with your [connection] sections."
      return 1
    fi

    # Get connection names
    mapfile -t connections < <(grep -oP '(?<=^\[).*?(?=\])' "$CONFIG_FILE")
    if [[ ${#connections[@]} -eq 0 ]]; then
      log_error "No [sections] found in $CONFIG_FILE"
      return 1
    fi

    local connection
    if ! menu_select_one "Select connection" "[${AWS_PROFILE:-port-forwarding}]" connection "${connections[@]}"; then
      return 1
    fi

    # Read config values
    local profile region port local_port host url name
    profile=$(aws_ssm_config_get "$CONFIG_FILE" "$connection" "profile")
    region=$(aws_ssm_config_get "$CONFIG_FILE" "$connection" "region")
    port=$(aws_ssm_config_get "$CONFIG_FILE" "$connection" "port")
    local_port=$(aws_ssm_config_get "$CONFIG_FILE" "$connection" "local_port")
    host=$(aws_ssm_config_get "$CONFIG_FILE" "$connection" "host")
    url=$(aws_ssm_config_get "$CONFIG_FILE" "$connection" "url")
    name=$(aws_ssm_config_get "$CONFIG_FILE" "$connection" "name")

    if [[ -z "$profile" || -z "$region" || -z "$port" ]]; then
      log_error "Invalid config for [$connection] - require profile, region, port"
      return 1
    fi

    local_port="${local_port:-$port}"
    host="${host:-localhost}"

    # Switch profile if needed
    if [[ "${AWS_PROFILE:-}" != "$profile" || "${AWS_REGION:-}" != "$region" ]]; then
    log_info "Switching to profile $profile ($region)"
      # Source the assume script to set environment variables
      if ! aws_assume_profile "$profile" "$region"; then
        log_error "Failed to assume profile $profile"
        return 1
      fi
    fi

    # Resolve instance
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
      if ! menu_select_one "Select instance for port forwarding" "[${AWS_PROFILE:-port-forwarding}]" chosen "${INSTANCE_LIST[@]}"; then
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

  # Non-config mode: interactive shell
  local target="${1:-}"
  local instance_id instance_name

  # If no AWS profile is set, prompt for profile and region
  if [[ -z "${AWS_PROFILE:-}" ]]; then
    local profiles
    profiles=$(aws_list_profiles)
    local all_profiles
    mapfile -t all_profiles <<<"$profiles"

    if [[ ${#all_profiles[@]} -eq 0 ]]; then
      log_error "No AWS profiles found"
      return 1
    fi

    local selected_profile=""
    if ! menu_select_one "Select AWS profile" "" selected_profile "${all_profiles[@]}"; then
      log_error "Profile selection cancelled"
      return 1
    fi

    local selected_region=""
    if ! menu_select_one "Select region for $selected_profile" "" selected_region "${AWS_REGIONS[@]}"; then
      selected_region="us-east-1"
      log_warn "No region selected, defaulting to us-east-1"
    fi

    log_info "Switching to profile $selected_profile ($selected_region)"
    if ! aws_assume_profile "$selected_profile" "$selected_region"; then
      log_error "Failed to assume profile $selected_profile"
      return 1
    fi
  fi

  if [[ -z "$target" ]]; then
    aws_get_all_running_instances ""
    if [[ ${#INSTANCE_LIST[@]} -eq 0 ]]; then
      echo "No running instances found"
      return 1
    fi
    local chosen
    if ! menu_select_one "Select instance to connect to" "[${AWS_PROFILE}]" chosen "${INSTANCE_LIST[@]}"; then
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

# Load saved commands from config files
# Priority order:
#   1. AWS_SSM_COMMAND_FILE environment variable (if set)
#   2. User config: ~/.config/aws-ssm-tools/commands.user.config
#   3. Default config: ~/.local/share/aws-ssm-tools/commands.config (shipped with tool)
# User/custom commands with same name override default commands
# Sets global arrays: COMMAND_NAMES, COMMAND_DESCRIPTIONS, COMMAND_STRINGS
aws_ssm_load_commands() {
  local default_config="$HOME/.local/share/aws-ssm-tools/commands.config"
  local user_config="$HOME/.config/aws-ssm-tools/commands.user.config"
  local custom_config="${AWS_SSM_COMMAND_FILE:-}"
  
  # Try alternate location for default config if not in standard location
  if [[ ! -f "$default_config" ]]; then
    local script_dir="$(cd -- "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
    local alt_config="${script_dir}/../commands.config"
    if [[ -f "$alt_config" ]]; then
      default_config="$alt_config"
    fi
  fi
  
  COMMAND_NAMES=()
  COMMAND_DESCRIPTIONS=()
  COMMAND_STRINGS=()
  
  # Helper function to load commands from a file
  load_from_file() {
    local file="$1"
    [[ ! -f "$file" ]] && return 0
    
    while IFS='|' read -r name desc cmd; do
      # Skip comments and empty lines
      [[ "$name" =~ ^#.*$ ]] && continue
      [[ -z "$name" ]] && continue
      
      # Check if command already exists (for user override)
      local found=false
      local i
      for i in "${!COMMAND_NAMES[@]}"; do
        if [[ "${COMMAND_NAMES[$i]}" == "$name" ]]; then
          # Override existing command
          COMMAND_DESCRIPTIONS[$i]="$desc"
          COMMAND_STRINGS[$i]="$cmd"
          found=true
          break
        fi
      done
      
      # Add new command if not found
      if [[ "$found" == false ]]; then
        COMMAND_NAMES+=("$name")
        COMMAND_DESCRIPTIONS+=("$desc")
        COMMAND_STRINGS+=("$cmd")
      fi
    done < "$file"
  }
  
  # Load default commands first
  if [[ -f "$default_config" ]]; then
    load_from_file "$default_config"
  fi
  
  # Load user commands (will override defaults with same name)
  if [[ -f "$user_config" ]]; then
    load_from_file "$user_config"
  fi
  
  # Load custom config from environment variable (will override both default and user)
  if [[ -n "$custom_config" ]]; then
    if [[ -f "$custom_config" ]]; then
      load_from_file "$custom_config"
    else
      log_warn "AWS_SSM_COMMAND_FILE set but file not found: $custom_config"
    fi
  fi
  
  # Return error if no commands loaded
  if [[ ${#COMMAND_NAMES[@]} -eq 0 ]]; then
    return 1
  fi
  
  return 0
}

# Select a command from the config file using fzf
# Returns the command string in the result_var
aws_ssm_select_command() {
  local __result_var="$1"
  
  if ! aws_ssm_load_commands; then
    log_error "No commands found. Default commands should be in ~/.local/share/aws-ssm-tools/commands.config"
    log_error "Create custom commands in ~/.config/aws-ssm-tools/commands.user.config"
    log_error "Or set AWS_SSM_COMMAND_FILE environment variable to a custom config file"
    return 1
  fi
  
  if [[ ${#COMMAND_NAMES[@]} -eq 0 ]]; then
    log_error "No commands found in config file"
    return 1
  fi
  
  # Build display array with name and description
  local display_items=()
  local i
  for i in "${!COMMAND_NAMES[@]}"; do
    display_items+=("${COMMAND_NAMES[$i]}: ${COMMAND_DESCRIPTIONS[$i]}")
  done
  
  local selected
  if ! menu_select_one "Select command to execute" "Saved SSM Commands" selected "${display_items[@]}"; then
    log_error "No command selected"
    return 1
  fi
  
  # Extract the command name from selection
  local selected_name="${selected%%:*}"
  
  # Find the corresponding command
  for i in "${!COMMAND_NAMES[@]}"; do
    if [[ "${COMMAND_NAMES[$i]}" == "$selected_name" ]]; then
      local cmd="${COMMAND_STRINGS[$i]}"
      # Expand variables in the command (e.g., $(cat ~/.ssh/id_rsa.pub))
      cmd=$(eval "echo \"$cmd\"")
      printf -v "$__result_var" '%s' "$cmd"
      return 0
    fi
  done
  
  log_error "Command not found: $selected_name"
  return 1
}

aws_ssm_execute_usage() {
  cat <<EOF
Usage:
  aws-ssm-exec '<command>' [INSTANCE ...]     # execute specific command
  aws-ssm-exec '<command>'                    # interactive instance selection
  aws-ssm-exec --select [INSTANCE ...]        # select command from saved commands
  aws-ssm-exec -s [INSTANCE ...]              # short form of --select
EOF
}

aws_ssm_execute_main() {
  local command=""
  local select_mode=false
  
  # Parse arguments
  if [[ "$#" -lt 1 ]]; then
    aws_ssm_execute_usage
    return 1
  fi
  
  # Check if first argument is --select or -s
  if [[ "$1" == "--select" ]] || [[ "$1" == "-s" ]]; then
    select_mode=true
    shift
  else
    command="$1"
    shift
  fi
  
  local instance_ids=("$@")
  
  # If in select mode, prompt for command selection
  if [[ "$select_mode" == true ]]; then
    if ! aws_ssm_select_command command; then
      return 1
    fi
    log_info "Selected command: $command"
  fi

  # If no profile is set, prompt for profile and region selection
  if [[ -z "${AWS_PROFILE:-}" ]]; then
    local profiles
    profiles=$(aws_list_profiles)
    local all_profiles
    mapfile -t all_profiles <<<"$profiles"

    if [[ ${#all_profiles[@]} -eq 0 ]]; then
      log_error "No AWS profiles found"
      return 1
    fi

    local selected_profile=""
    if ! menu_select_one "Select AWS profile" "" selected_profile "${all_profiles[@]}"; then
      log_error "Profile selection cancelled"
      return 1
    fi

    local selected_region=""
    if ! menu_select_one "Select region for $selected_profile" "" selected_region "${AWS_REGIONS[@]}"; then
      selected_region="us-east-1"
      log_warn "No region selected, defaulting to us-east-1"
    fi

    log_info "Switching to profile $selected_profile ($selected_region)"
    if ! aws_assume_profile "$selected_profile" "$selected_region"; then
      log_error "Failed to assume profile $selected_profile"
      return 1
    fi
  fi

  if [[ ${#instance_ids[@]} -eq 0 ]]; then
    aws_get_all_running_instances ""
    if [[ ${#INSTANCE_LIST[@]} -eq 0 ]]; then
      echo "No running instances found"
      return 1
    fi
    # selections will be set by menu_select_multi using declare -g
    # Initialize but do NOT declare as local - declare -g can't modify caller's local vars
    selections=""
    if ! menu_select_multi "Select instances for SSM command" selections "${INSTANCE_LIST[@]}"; then
      [[ -n "${DEBUG_AWS_SSM:-}" ]] && echo "DEBUG: menu_select_multi returned error" >&2
      return 1
    fi

    [[ -n "${DEBUG_AWS_SSM:-}" ]] && echo "DEBUG: selections value: [$selections]" >&2
    [[ -n "${DEBUG_AWS_SSM:-}" ]] && echo "DEBUG: selections length: ${#selections}" >&2

    # Check if selections is empty (menu returned success but nothing selected)
    if [[ -z "${selections:-}" ]]; then
      echo "No instances selected"
      return 1
    fi

    # Extract IDs using mapfile to avoid subshell/process substitution issues
    local selected_lines
    mapfile -t selected_lines <<<"$selections"

    local item
    for item in "${selected_lines[@]}"; do
      [[ -z "$item" ]] && continue
      local extracted_id="${item##* }"
      instance_ids+=("$extracted_id")
    done
  fi

  if [[ ${#instance_ids[@]} -eq 0 ]]; then
    echo "No instances selected"
    return 1
  fi

  local tmpfile
  tmpfile=$(mktemp /tmp/ssm-script.XXXXXX)
  trap 'rm -f "${tmpfile:-}"' EXIT

  cat >"$tmpfile" <<EOF
{
  "Parameters": {
    "commands": [
      "#!/bin/bash",
      "$command"
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
    for inst in "${instance_ids[@]}"; do
      local status
      status=$(aws ssm get-command-invocation \
        --command-id "$cmd_id" \
        --instance-id "$inst" \
        --query Status \
        --output text | tr 'A-Z' 'a-z')
      local now
      now=$(date +%Y-%m-%dT%H:%M:%S%z)
      echo "$now $inst: $status"
      case "$status" in
      pending | inprogress | delayed) : ;;
      *) finished=$((finished + 1)) ;;
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
  [[ -n "${DEBUG_AWS_SSM:-}" ]] && echo "DEBUG: About to return 0" >&2
  local exit_code=0
  [[ -n "${DEBUG_AWS_SSM:-}" ]] && echo "DEBUG: exit_code set to $exit_code" >&2
  return $exit_code
}

aws_ssm_list_main() {
  local current_profile="${AWS_PROFILE:-none}"
  echo "Active SSM sessions (Current profile: $current_profile):"

  ps aux | grep "session-manager-plugin" | grep -v grep | while read -r line; do
    local pid target host port session_type instance_name
    pid=$(awk '{print $2}' <<<"$line")
    target=$(grep -oP '\-\-target \K[^ ]+' <<<"$line" || true)
    [[ -z "$target" ]] && target=$(sed -n 's/.*TargetId":"\([^"]*\)".*/\1/p' <<<"$line" | head -n1)

    if grep -q "StartPortForwardingSessionToRemoteHost" <<<"$line"; then
      port=$(sed -n 's/.*localPortNumber":\["\([0-9]*\)".*/\1/p' <<<"$line" | head -n1)
      host=$(sed -n 's/.*"host":\["\([^"]*\)".*/\1/p' <<<"$line" | head -n1)
      [[ -z "$host" ]] && host="localhost"
      session_type="Port: ${port:-?} -> ${host}"
    elif grep -q "StartPortForwardingSession" <<<"$line"; then
      port=$(sed -n 's/.*localPortNumber":\["\([0-9]*\)".*/\1/p' <<<"$line" | head -n1)
      host=$(sed -n 's/.*DestinationHost":"\([^"]*\)".*/\1/p' <<<"$line" | head -n1)
      [[ -z "$host" ]] && host="localhost"
      session_type="Port: ${port:-?} -> ${host}"
    else
      session_type="Interactive Shell"
    fi

    instance_name=""
    if [[ -n "$target" ]]; then
      instance_name=$(aws ec2 describe-instances --instance-ids "$target" \
        --query "Reservations[0].Instances[0].Tags[?Key=='Name'].Value" \
        --output text 2>/dev/null || echo "")
    fi

    if [[ -n "$instance_name" && "$instance_name" != "None" ]]; then
      echo "  PID: $pid | $session_type | Instance: $instance_name (${target:-unknown})"
    else
      echo "  PID: $pid | $session_type | Instance: ${target:-unknown}"
    fi
  done

  echo ""
  echo "Tip: Switch to the correct AWS profile to see instance names"
}

aws_ssm_kill_main() {
  mapfile -t sessions < <(ps aux | grep "session-manager-plugin" | grep -v grep)
  if [[ ${#sessions[@]} -eq 0 ]]; then
    echo "No active SSM sessions found."
    return 0
  fi

  local session_list=()
  local pid_list=()
  for line in "${sessions[@]}"; do
    local pid target host port session_type instance_name
    pid=$(awk '{print $2}' <<<"$line")
    target=$(grep -oP '\-\-target \K[^ ]+' <<<"$line" || true)
    [[ -z "$target" ]] && target=$(sed -n 's/.*TargetId":"\([^"]*\)".*/\1/p' <<<"$line" | head -n1)

    if grep -q "StartPortForwardingSessionToRemoteHost" <<<"$line"; then
      port=$(sed -n 's/.*localPortNumber":\["\([0-9]*\)".*/\1/p' <<<"$line" | head -n1)
      host=$(sed -n 's/.*"host":\["\([^"]*\)".*/\1/p' <<<"$line" | head -n1)
      [[ -z "$host" ]] && host="localhost"
      session_type="Port: ${port:-?} -> ${host}"
    elif grep -q "StartPortForwardingSession" <<<"$line"; then
      port=$(sed -n 's/.*localPortNumber":\["\([0-9]*\)".*/\1/p' <<<"$line" | head -n1)
      host=$(sed -n 's/.*DestinationHost":"\([^"]*\)".*/\1/p' <<<"$line" | head -n1)
      [[ -z "$host" ]] && host="localhost"
      session_type="Port: ${port:-?} -> ${host}"
    else
      session_type="Interactive Shell"
    fi

    instance_name=""
    if [[ -n "$target" ]]; then
      instance_name=$(aws ec2 describe-instances --instance-ids "$target" \
        --query "Reservations[0].Instances[0].Tags[?Key=='Name'].Value" \
        --output text 2>/dev/null || echo "")
    fi

    if [[ -n "$instance_name" && "$instance_name" != "None" ]]; then
      session_list+=("PID: $pid | $session_type | Instance: $instance_name (${target:-unknown})")
    else
      session_list+=("PID: $pid | $session_type | Instance: ${target:-unknown}")
    fi
    pid_list+=("$pid")
  done

  # selected will be set by menu_select_multi using declare -g
  # Do NOT declare as local - declare -g can't modify caller's local vars
  selected=""
  if ! menu_select_multi "Select SSM sessions to kill" selected "${session_list[@]}"; then
    return 0
  fi

  if [[ -z "${selected:-}" ]]; then
    echo "No sessions selected"
    return 0
  fi

  while IFS= read -r sel; do
    [[ -z "$sel" ]] && continue
    local pid
    pid=$(grep -oP 'PID: \K[0-9]+' <<<"$sel" || true)
    if [[ -n "$pid" ]]; then
      echo "Killing SSM session PID: $pid"
      # Try graceful kill first, then force kill if needed
      if kill "$pid" 2>/dev/null; then
        sleep 0.5
        if ps -p "$pid" >/dev/null 2>&1; then
          echo "  Process still running, forcing kill..."
          kill -9 "$pid" 2>/dev/null || log_error "Failed to force kill PID $pid"
        fi
        log_info "Session $pid terminated"
      else
        log_error "Failed to kill PID $pid"
      fi
    fi
  done <<<"$selected"
}
