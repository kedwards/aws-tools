#!/usr/bin/env bash

ssm_login_usage() {
  cat <<EOF
Usage: ssm login [OPTIONS]

Authenticate with AWS via Granted (assume).

Options:
  -p, --profile PROFILE  AWS profile to assume
  -r, --region REGION    AWS region
  -h, --help             Show this help message

Examples:
  ssm login                      # Interactive profile/region selection
  ssm login -p myprofile         # Login to specific profile
  ssm login -p prod -r us-west-2 # Login with profile and region
EOF
}

ssm_login() {
  parse_common_flags "$@" || return 1

  if [[ "${SHOW_HELP:-false}" == true ]]; then
    ssm_login_usage
    return 0
  fi

  choose_profile_and_region || return 1
  aws_auth_login "$PROFILE" "$REGION" || return 1
}
