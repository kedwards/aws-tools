#!/usr/bin/env bash

ssm_list_usage() {
  cat <<EOF
Usage: ssm list

List active SSM sessions on this host.
EOF
}

ssm_list() {
  if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    ssm_list_usage
    return 0
  fi

  local current_profile="${AWS_PROFILE:-none}"
  echo "Active SSM sessions (Current profile: $current_profile):"

  mapfile -t lines < <(ps aux | grep "session-manager-plugin" | grep -v grep || true)
  if [[ ${#lines[@]} -eq 0 ]]; then
    echo "  (none found)"
    return 0
  fi

  local line
  for line in "${lines[@]}"; do
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
