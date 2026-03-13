#!/usr/bin/env bats
# shellcheck disable=SC2329,SC2030,SC2031

export MENU_NON_INTERACTIVE=1
export AWS_EC2_DISABLE_LIVE_CALLS=1
export AWS_AUTH_DISABLE_ASSUME=1

load '../helpers/bats-support/load'
load '../helpers/bats-assert/load'

# Stub logging
log_debug()   { :; }
log_info()    { :; }
log_warn()    { :; }
log_error()   { echo "$*" >&2; }
log_success() { echo "$*"; }

setup() {
  # Reset global flags
  SHOW_HELP=false
  PROFILE=""
  REGION=""

  # Stub dependencies
  parse_common_flags() { return 0; }
  choose_profile_and_region() { return 0; }
  aws_auth_login() { echo "AUTH_LOGIN: $1 $2"; return 0; }

  source ./lib/commands/ssm_login.sh
}

@test "ssm_login_usage displays help text" {
  run ssm_login_usage

  assert_success
  assert_output --partial "Usage: ssm login"
  assert_output --partial "-p, --profile"
  assert_output --partial "-r, --region"
  assert_output --partial "Examples:"
}

@test "ssm_login shows help with --help flag" {
  SHOW_HELP=true

  run ssm_login

  assert_success
  assert_output --partial "Usage: ssm login"
}

@test "ssm_login shows help with real flag parsing" {
  unset -f parse_common_flags
  source ./lib/core/flags.sh

  run ssm_login --help

  assert_success
  assert_output --partial "Usage: ssm login"
}

@test "ssm_login calls choose_profile_and_region" {
  choose_profile_and_region() {
    echo "CHOOSE_CALLED"
    PROFILE="testprofile"
    REGION="us-east-1"
    return 0
  }

  run ssm_login

  assert_success
  assert_output --partial "CHOOSE_CALLED"
}

@test "ssm_login fails when choose_profile_and_region fails" {
  choose_profile_and_region() { return 1; }

  run ssm_login

  assert_failure
}

@test "ssm_login calls aws_auth_login with profile and region" {
  PROFILE="prod"
  REGION="us-west-2"

  run ssm_login

  assert_success
  assert_output --partial "AUTH_LOGIN: prod us-west-2"
}

@test "ssm_login fails when aws_auth_login fails" {
  aws_auth_login() { return 1; }
  PROFILE="prod"
  REGION="us-west-2"

  run ssm_login

  assert_failure
}

@test "ssm_login fails when parse_common_flags fails" {
  parse_common_flags() { return 1; }

  run ssm_login

  assert_failure
}
