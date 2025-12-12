#!/usr/bin/env bash

parse_common_flags() {
  PROFILE=""
  REGION=""
  INSTANCE=""
  INSTANCES_ARG=""
  CONFIG_MODE=false
  CONFIG_FILE=""
  COMMAND_ARG=""
  SHOW_HELP=false
  POSITIONAL=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -p|--profile)
        shift
        if [[ $# -eq 0 ]]; then
          log_error "Option -p/--profile requires an argument"
          return 1
        fi
        PROFILE="$1"
        shift
        ;;
      -r|--region)
        shift
        if [[ $# -eq 0 ]]; then
          log_error "Option -r/--region requires an argument"
          return 1
        fi
        REGION="$1"
        shift
        ;;
      -i|--instance|--instances)
        shift
        if [[ $# -eq 0 ]]; then
          log_error "Option -i/--instances requires an argument"
          return 1
        fi
        INSTANCES_ARG="$1"
        shift
        ;;
      -c|--config)
        # Check if next arg looks like a flag or if -c is used for config mode
        if [[ ${#POSITIONAL[@]} -eq 0 ]] && [[ "${2:-}" != -* ]] && [[ -n "${2:-}" ]]; then
          # This is -c <command> syntax (for exec)
          shift
          COMMAND_ARG="$1"
          shift
        else
          # This is --config flag (for connect port-forward mode)
          CONFIG_MODE=true
          shift
        fi
        ;;
      -f|--file)
        shift
        if [[ $# -eq 0 ]]; then
          log_error "Option -f/--file requires an argument"
          return 1
        fi
        CONFIG_FILE="$1"
        shift
        ;;
      -e|--exec|--command)
        shift
        if [[ $# -eq 0 ]]; then
          log_error "Option -e requires an argument"
          return 1
        fi
        # Check if -e contains profile:region syntax (for backward compat with main)
        if [[ "$1" =~ ^([^:]+):(.+)$ ]]; then
          # This is profile:region syntax
          PROFILE="${BASH_REMATCH[1]}"
          REGION="${BASH_REMATCH[2]}"
        elif [[ "$1" =~ ^[a-zA-Z0-9_-]+$ ]]; then
          # This looks like a profile name (no spaces, no special chars)
          # Check if it's actually a profile or a command
          if [[ -z "$COMMAND_ARG" ]] && [[ "${2:-}" == -* || $# -eq 1 ]]; then
            # Likely a profile if followed by a flag or is last arg
            PROFILE="$1"
          else
            # Treat as command
            COMMAND_ARG="$1"
          fi
        else
          # Contains spaces or special chars, must be a command
          COMMAND_ARG="$1"
        fi
        shift
        ;;
      -h|--help)
        SHOW_HELP=true
        shift
        ;;
      --)
        shift
        break
        ;;
      -*)
        log_error "Unknown flag: $1"
        return 1
        ;;
      *)
        POSITIONAL+=("$1")
        shift
        ;;
    esac
  done
  
  # Add any remaining args to POSITIONAL
  while [[ $# -gt 0 ]]; do
    POSITIONAL+=("$1")
    shift
  done
}
