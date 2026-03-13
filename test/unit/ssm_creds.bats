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
  source ./lib/commands/ssm_creds.sh
}

@test "ssm_creds shows usage with no arguments" {
  run ssm_creds

  assert_success
  assert_output --partial "Usage: ssm creds <store|use>"
  assert_output --partial "store <env>"
  assert_output --partial "use"
}

@test "ssm_creds shows usage with unknown subcommand" {
  run ssm_creds unknown

  assert_success
  assert_output --partial "Usage: ssm creds <store|use>"
}

@test "ssm_creds store shows help with no env" {
  run ssm_creds store

  assert_success
  assert_output --partial "Usage: ssm creds store <env>"
  assert_output --partial "Requires: assume (Granted)"
}

@test "ssm_creds store shows help with -h" {
  run ssm_creds store -h

  assert_success
  assert_output --partial "Usage: ssm creds store <env>"
}

@test "ssm_creds store shows help with --help" {
  run ssm_creds store --help

  assert_success
  assert_output --partial "Usage: ssm creds store <env>"
}

@test "ssm_creds store fails when assume not in PATH" {
  export AWS_AUTH_DISABLE_ASSUME=0

  # Override command to simulate assume not found
  command() {
    if [[ "$1" == "-v" && "$2" == "assume" ]]; then
      return 1
    fi
    builtin command "$@"
  }

  run ssm_creds store myenv

  assert_failure
  assert_output --partial "'assume' (Granted) not found in PATH"
}

@test "ssm_creds store skips when AWS_AUTH_DISABLE_ASSUME is set" {
  export AWS_AUTH_DISABLE_ASSUME=1

  # Stub assume to verify it's not called
  assume() {
    echo "SHOULD_NOT_RUN"
    return 99
  }

  command() {
    if [[ "$1" == "-v" && "$2" == "assume" ]]; then
      return 0
    fi
    builtin command "$@"
  }

  run ssm_creds store myenv

  assert_success
  refute_output --partial "SHOULD_NOT_RUN"
}

@test "ssm_creds use outputs export with stored vars" {
  export AK="AKIATEST123"
  export SK="SECRET456"
  export ST="TOKEN789"

  run ssm_creds use

  assert_success
  assert_output --partial "export AWS_ACCESS_KEY_ID=\"AKIATEST123\""
  assert_output --partial "AWS_SECRET_ACCESS_KEY=\"SECRET456\""
  assert_output --partial "AWS_SESSION_TOKEN=\"TOKEN789\""
}

@test "ssm_creds use outputs empty values when no stored vars" {
  unset AK SK ST

  run ssm_creds use

  assert_success
  assert_output --partial 'AWS_ACCESS_KEY_ID=""'
  assert_output --partial 'AWS_SECRET_ACCESS_KEY=""'
  assert_output --partial 'AWS_SESSION_TOKEN=""'
}

@test "ssm_creds dispatches store subcommand" {
  # Stub ssm_creds_store to verify dispatch
  ssm_creds_store() {
    echo "STORE_CALLED: $*"
  }

  run ssm_creds store myenv

  assert_success
  assert_output --partial "STORE_CALLED: myenv"
}

@test "ssm_creds dispatches use subcommand" {
  # Stub ssm_creds_use to verify dispatch
  ssm_creds_use() {
    echo "USE_CALLED"
  }

  run ssm_creds use

  assert_success
  assert_output --partial "USE_CALLED"
}
