#!/usr/bin/env bats
# shellcheck disable=SC2329

export MENU_NON_INTERACTIVE=1
export AWS_EC2_DISABLE_LIVE_CALLS=1
export AWS_AUTH_DISABLE_ASSUME=1

source ./lib/menu/index.sh
source ./lib/core/aws_auth.sh

load '../helpers/bats-support/load'
load '../helpers/bats-assert/load'

setup() {
  log_error(){ echo "$*" >&2; }
  export MENU_NON_INTERACTIVE=1

  # AWS stub
  aws() { return 1; }
}

@test "menu_select_one fails in non-interactive mode" {
  run menu_select_one "prompt" "" out a b
  assert_failure
  assert_output --partial "not allowed in non-interactive mode"
}

@test "aws_auth_assume fails fast without credentials" {
  unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
  aws() { return 1; }  # STS call fails

  run aws_auth_assume test us-west-2

  assert_failure
  assert_output --partial "No AWS credentials found"
  assert_output --partial "Authenticate first with: ssm login"
}

