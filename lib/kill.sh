#!/usr/bin/env bash

ssm_kill_usage() {
  cat <<EOF
Usage: ssm kill

Interactively select and terminate SSM sessions on this host.
EOF
}

ssm_kill() {
  if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    ssm_kill_usage
    return 0
  fi

  mapfile -t sessions < <(ps aux | grep "session-manager-plugin" | grep -v grep || true)
  if [[ ${#sessions[@]} -eq 0 ]]; then
    echo "No active SSM sessions found."
    return 0
  fi

  local session_list=()
  local line
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
  done

  local selected
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
