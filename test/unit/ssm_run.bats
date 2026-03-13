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
log_warn()    { echo "[WARN] $*"; }
log_error()   { echo "[ERROR] $*" >&2; }
log_success() { :; }

setup() {
  TEST_TMPDIR="$(mktemp -d)"
  CMD_DIR="$TEST_TMPDIR/commands"
  mkdir -p "$CMD_DIR"

  # Stub aws_auth_login to succeed and record calls
  aws_auth_login() {
    echo "LOGIN: $1 $2"
    return 0
  }

  # Stub aws_list_profiles
  aws_list_profiles() {
    printf '%s\n' "dev" "prod"
  }

  export AWS_TOOLS_CMD_DIR="$CMD_DIR"
  source ./lib/commands/ssm_run.sh
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

# --- Help ---

@test "ssm_run_usage displays help text" {
  run ssm_run_usage

  assert_success
  assert_output --partial "Usage: ssm run"
  assert_output --partial "-q <command>"
  assert_output --partial "-d <path>"
  assert_output --partial "#ENV"
  assert_output --partial "#REGION"
}

@test "ssm_run shows help with -h" {
  run ssm_run -h

  assert_success
  assert_output --partial "Usage: ssm run"
}

@test "ssm_run shows help with --help" {
  run ssm_run --help

  assert_success
  assert_output --partial "Usage: ssm run"
}

# --- List commands ---

@test "ssm_run with no args lists available commands" {
  # Create a snippet file
  cat > "$CMD_DIR/vpc-cidrs" <<'SNIPPET'
# aws-tools command
# VPC CIDRs and names
aws ec2 describe-vpcs --output table
SNIPPET

  run ssm_run

  assert_success
  assert_output --partial "Available commands"
  assert_output --partial "vpc-cidrs"
  assert_output --partial "VPC CIDRs and names"
}

@test "ssm_run list marks executable scripts" {
  cat > "$CMD_DIR/instances" <<'SCRIPT'
#!/usr/bin/env bash
# Running instances with AMI info
echo hello
SCRIPT
  chmod +x "$CMD_DIR/instances"

  run ssm_run

  assert_success
  assert_output --partial "instances"
  assert_output --partial "*"
}

@test "ssm_run fails when commands dir does not exist" {
  export AWS_TOOLS_CMD_DIR="$TEST_TMPDIR/nonexistent"

  run ssm_run

  assert_failure
  assert_output --partial "Commands directory not found"
}

# --- Executable scripts ---

@test "ssm_run runs executable script directly without filter" {
  cat > "$CMD_DIR/myscript" <<'SCRIPT'
#!/usr/bin/env bash
echo "SCRIPT_RAN"
SCRIPT
  chmod +x "$CMD_DIR/myscript"

  run ssm_run myscript

  assert_success
  assert_output --partial "SCRIPT_RAN"
  # Should NOT iterate profiles
  refute_output --partial "LOGIN:"
}

@test "ssm_run runs executable script per profile with filter" {
  cat > "$CMD_DIR/myscript" <<'SCRIPT'
#!/usr/bin/env bash
echo "SCRIPT_RAN"
SCRIPT
  chmod +x "$CMD_DIR/myscript"

  run ssm_run myscript "dev prod"

  assert_success
  assert_output --partial "LOGIN: dev us-east-1"
  assert_output --partial "LOGIN: prod us-east-1"
  # Script runs twice
  local count
  count=$(echo "$output" | grep -c "SCRIPT_RAN")
  [ "$count" -eq 2 ]
}

# --- Snippet files ---

@test "ssm_run resolves and evals snippet file content" {
  cat > "$CMD_DIR/test-snippet" <<'SNIPPET'
# aws-tools command
# Test snippet
echo "SNIPPET_OUTPUT"
SNIPPET

  run ssm_run test-snippet "dev"

  assert_success
  assert_output --partial "LOGIN: dev us-east-1"
  assert_output --partial "SNIPPET_OUTPUT"
}

@test "ssm_run strips comments and blank lines from snippets" {
  cat > "$CMD_DIR/commented" <<'SNIPPET'
# First comment
# Second comment

echo "ONLY_THIS"
SNIPPET

  run ssm_run commented "dev"

  assert_success
  assert_output --partial "ONLY_THIS"
  refute_output --partial "First comment"
}

# --- Placeholder substitution ---

@test "ssm_run substitutes #ENV placeholder" {
  cat > "$CMD_DIR/env-test" <<'SNIPPET'
# test
# env placeholder test
echo "PROFILE=#ENV"
SNIPPET

  run ssm_run env-test "myprofile"

  assert_success
  assert_output --partial "PROFILE=myprofile"
}

@test "ssm_run substitutes #REGION placeholder" {
  cat > "$CMD_DIR/region-test" <<'SNIPPET'
# test
# region placeholder test
echo "REGION=#REGION"
SNIPPET

  run ssm_run region-test "myprofile:us-west-2"

  assert_success
  assert_output --partial "REGION=us-west-2"
}

@test "ssm_run substitutes both #ENV and #REGION" {
  cat > "$CMD_DIR/both-test" <<'SNIPPET'
# test
# both placeholders
echo "#ENV in #REGION"
SNIPPET

  run ssm_run both-test "staging:eu-west-1"

  assert_success
  assert_output --partial "staging in eu-west-1"
}

# --- Profile/region parsing ---

@test "ssm_run defaults region to us-east-1 when not specified" {
  cat > "$CMD_DIR/noop" <<'SNIPPET'
# test
# noop
echo "ok"
SNIPPET

  run ssm_run noop "myprofile"

  assert_success
  assert_output --partial "LOGIN: myprofile us-east-1"
}

@test "ssm_run parses profile:region filter pairs" {
  cat > "$CMD_DIR/noop" <<'SNIPPET'
# test
# noop
echo "ok"
SNIPPET

  run ssm_run noop "dev:us-west-2 prod:eu-west-1"

  assert_success
  assert_output --partial "LOGIN: dev us-west-2"
  assert_output --partial "LOGIN: prod eu-west-1"
}

@test "ssm_run iterates all profiles when no filter" {
  cat > "$CMD_DIR/noop" <<'SNIPPET'
# test
# noop
echo "ok"
SNIPPET

  run ssm_run noop

  assert_success
  assert_output --partial "LOGIN: dev us-east-1"
  assert_output --partial "LOGIN: prod us-east-1"
}

@test "ssm_run fails when no profiles found" {
  aws_list_profiles() { :; }  # Returns nothing

  cat > "$CMD_DIR/noop" <<'SNIPPET'
# test
# noop
echo "ok"
SNIPPET

  run ssm_run noop

  assert_failure
  assert_output --partial "No profiles found"
}

# --- Inline queries ---

@test "ssm_run -q runs inline command across profiles" {
  run ssm_run -q "echo INLINE_CMD" "dev prod"

  assert_success
  assert_output --partial "LOGIN: dev us-east-1"
  assert_output --partial "LOGIN: prod us-east-1"
  local count
  count=$(echo "$output" | grep -c "INLINE_CMD")
  [ "$count" -eq 2 ]
}

@test "ssm_run -q with no filter uses all profiles" {
  run ssm_run -q "echo QUERY"

  assert_success
  assert_output --partial "LOGIN: dev us-east-1"
  assert_output --partial "LOGIN: prod us-east-1"
}

# --- Custom directory ---

@test "ssm_run -d overrides commands directory" {
  local alt_dir="$TEST_TMPDIR/alt-commands"
  mkdir -p "$alt_dir"

  cat > "$alt_dir/custom-cmd" <<'SNIPPET'
# custom
# Custom command
echo "CUSTOM_OUTPUT"
SNIPPET

  run ssm_run -d "$alt_dir" custom-cmd "dev"

  assert_success
  assert_output --partial "CUSTOM_OUTPUT"
}

@test "ssm_run -d lists commands from custom directory" {
  local alt_dir="$TEST_TMPDIR/alt-commands"
  mkdir -p "$alt_dir"

  cat > "$alt_dir/my-tool" <<'SNIPPET'
# custom
# My custom tool
echo "hi"
SNIPPET

  run ssm_run -d "$alt_dir"

  assert_success
  assert_output --partial "my-tool"
  assert_output --partial "My custom tool"
}

# --- Error handling ---

@test "ssm_run continues on login failure for a profile" {
  aws_auth_login() {
    if [[ "$1" == "badprofile" ]]; then
      return 1
    fi
    echo "LOGIN: $1 $2"
    return 0
  }

  cat > "$CMD_DIR/noop" <<'SNIPPET'
# test
# noop
echo "ok"
SNIPPET

  run ssm_run noop "badprofile goodprofile"

  assert_success
  assert_output --partial "[WARN] Failed to assume 'badprofile', skipping"
  assert_output --partial "LOGIN: goodprofile us-east-1"
}

@test "ssm_run uses raw command string when no matching file" {
  run ssm_run "echo RAW_CMD" "dev"

  assert_success
  assert_output --partial "RAW_CMD"
}
