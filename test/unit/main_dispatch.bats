#!/usr/bin/env bats
# shellcheck disable=SC2034

export MENU_NON_INTERACTIVE=1
export AWS_EC2_DISABLE_LIVE_CALLS=1
export AWS_AUTH_DISABLE_ASSUME=1

setup() {
  # Stub logging
  log_debug() { :; }
  log_info() { :; }
  log_warn() { :; }
  log_error() { :; }
  export -f log_debug log_info log_warn log_error
}

# main dispatch tests

@test "bin/ssm shows help with --help" {
  run ./bin/ssm --help
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Usage: ssm" ]]
  [[ "$output" =~ "Commands:" ]]
  [[ "$output" =~ "login" ]]
  [[ "$output" =~ "connect" ]]
  [[ "$output" =~ "exec" ]]
  [[ "$output" =~ "run" ]]
  [[ "$output" =~ "creds" ]]
  [[ "$output" =~ "list" ]]
  [[ "$output" =~ "kill" ]]
}

@test "bin/ssm shows help with -h" {
  run ./bin/ssm -h
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Usage: ssm" ]]
}

@test "bin/ssm with no command shows help and exits with error" {
  run ./bin/ssm
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Usage: ssm" ]]
}

@test "bin/ssm list runs successfully" {
  run ./bin/ssm list
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Active SSM sessions" ]]
}

@test "bin/ssm shows error for unknown command" {
  run ./bin/ssm unknown-cmd
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Unknown command" ]]
}

@test "bin/ssm list --help works" {
  run ./bin/ssm list --help
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Usage: ssm list" ]]
}

@test "bin/ssm kill --help works" {
  run ./bin/ssm kill --help
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Usage: ssm kill" ]]
}

@test "bin/ssm kill runs successfully" {
  run ./bin/ssm kill
  [ "$status" -eq 0 ]
  [[ "$output" =~ "No active SSM sessions found" ]]
}

@test "bin/ssm exec --help works" {
  run ./bin/ssm exec --help
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Usage: ssm exec" ]]
  [[ "$output" =~ "Run a shell command via AWS SSM" ]]
}

@test "bin/ssm login --help works" {
  run ./bin/ssm login --help
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Usage: ssm login" ]]
  [[ "$output" =~ "Authenticate with AWS via Granted" ]]
}

@test "bin/ssm run --help works" {
  run ./bin/ssm run --help
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Usage: ssm run" ]]
  [[ "$output" =~ "Run a command or script" ]]
}

@test "bin/ssm creds shows usage" {
  run ./bin/ssm creds
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Usage: ssm creds" ]]
  [[ "$output" =~ "store" ]]
  [[ "$output" =~ "use" ]]
}
