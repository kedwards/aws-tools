#!/usr/bin/env bats
# shellcheck disable=SC2329,SC2030,SC2031
# Tests for ssm run multi-source directory layering priority.
#
# The layering rules under test:
#   1. Install dir  (~/.local/share/aws-ssm-tools/run-commands) is the shipped default
#   2. User dir     (~/.config/aws-ssm-tools/run-commands) overrides install dir by name
#   3. -d <path>    is an exclusive override — install and user dirs are ignored
#   4. AWS_TOOLS_CMD_DIR is an exclusive override — install and user dirs are ignored

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

  # Isolate HOME so _SSM_RUN_INSTALL_DIR and _SSM_RUN_USER_DIR resolve to test paths
  export HOME="$TEST_TMPDIR/home"
  mkdir -p "$HOME"

  # Ensure env-var override does not interfere with layering tests
  unset AWS_TOOLS_CMD_DIR

  # Stubs
  aws_auth_login() { echo "LOGIN: $1 $2"; return 0; }
  aws_list_profiles() { printf '%s\n' "dev" "prod"; }

  source ./lib/commands/ssm_run.sh

  # Export computed dir paths so subshells spawned by `run` can see them
  export _SSM_RUN_INSTALL_DIR _SSM_RUN_USER_DIR
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

# ── Helpers ──────────────────────────────────────────────────────────────────

# Create a non-executable snippet file
make_snippet() {
  local dir="$1" name="$2" desc="${3:-A description}"
  mkdir -p "$dir"
  printf '# aws-tools command\n# %s\necho "OUTPUT:%s"\n' "$desc" "$name" > "$dir/$name"
}

# Create an executable script
make_script() {
  local dir="$1" name="$2" desc="${3:-A description}"
  mkdir -p "$dir"
  printf '#!/usr/bin/env bash\n# %s\necho "OUTPUT:%s"\n' "$desc" "$name" > "$dir/$name"
  chmod +x "$dir/$name"
}

# ── Listing: single source ────────────────────────────────────────────────────

@test "list: shows commands from install dir when only install dir exists" {
  make_snippet "$_SSM_RUN_INSTALL_DIR" "vpc-cidrs" "VPC CIDRs"

  run ssm_run

  assert_success
  assert_output --partial "vpc-cidrs"
  assert_output --partial "VPC CIDRs"
}

@test "list: shows commands from user dir when only user dir exists" {
  make_snippet "$_SSM_RUN_USER_DIR" "my-cmd" "My custom command"

  run ssm_run

  assert_success
  assert_output --partial "my-cmd"
  assert_output --partial "My custom command"
}

@test "list: shows commands from both install and user dirs" {
  make_snippet "$_SSM_RUN_INSTALL_DIR" "install-cmd" "Install command"
  make_snippet "$_SSM_RUN_USER_DIR"    "user-cmd"    "User command"

  run ssm_run

  assert_success
  assert_output --partial "install-cmd"
  assert_output --partial "user-cmd"
}

@test "list: commands are sorted alphabetically across both dirs" {
  make_snippet "$_SSM_RUN_INSTALL_DIR" "z-last"  "Last command"
  make_snippet "$_SSM_RUN_USER_DIR"    "a-first"  "First command"

  run ssm_run

  assert_success
  # a-first should appear before z-last in output
  local pos_first pos_last
  pos_first=$(echo "$output" | grep -n "a-first" | cut -d: -f1)
  pos_last=$(echo  "$output" | grep -n "z-last"  | cut -d: -f1)
  [ "$pos_first" -lt "$pos_last" ]
}

# ── Listing: markers ─────────────────────────────────────────────────────────

@test "list: install dir commands have no + marker" {
  make_snippet "$_SSM_RUN_INSTALL_DIR" "install-cmd" "Install command"

  run ssm_run

  assert_success
  assert_output --partial "install-cmd"
  refute_output --partial "+"
}

@test "list: user dir commands have + marker" {
  make_snippet "$_SSM_RUN_USER_DIR" "user-cmd" "User command"

  run ssm_run

  assert_success
  assert_output --partial "+"
  assert_output --partial "+ = user-defined"
}

@test "list: executable script in install dir shows * marker" {
  make_script "$_SSM_RUN_INSTALL_DIR" "my-script" "My script"

  run ssm_run

  assert_success
  assert_output --partial "my-script"
  assert_output --partial "*"
  assert_output --partial "* = executable script"
}

@test "list: executable script in user dir shows *+ markers" {
  make_script "$_SSM_RUN_USER_DIR" "user-script" "User script"

  run ssm_run

  assert_success
  assert_output --partial "user-script"
  assert_output --partial "*+"
}

# ── Listing: same-name priority ───────────────────────────────────────────────

@test "list: user dir command description overrides install dir for same name" {
  make_snippet "$_SSM_RUN_INSTALL_DIR" "shared" "Default description"
  make_snippet "$_SSM_RUN_USER_DIR"    "shared" "User description"

  run ssm_run

  assert_success
  assert_output --partial "User description"
  refute_output --partial "Default description"
}

@test "list: same-name command appears only once (no duplicates)" {
  make_snippet "$_SSM_RUN_INSTALL_DIR" "shared" "Default description"
  make_snippet "$_SSM_RUN_USER_DIR"    "shared" "User description"

  run ssm_run

  assert_success
  local count
  count=$(echo "$output" | grep -c "shared")
  [ "$count" -eq 1 ]
}

@test "list: same-name command shows + marker when user dir wins" {
  make_snippet "$_SSM_RUN_INSTALL_DIR" "shared" "Default description"
  make_snippet "$_SSM_RUN_USER_DIR"    "shared" "User description"

  run ssm_run

  assert_success
  assert_output --partial "+"
}

# ── Execution: priority ───────────────────────────────────────────────────────

@test "execute: install dir script runs when no user override" {
  make_snippet "$_SSM_RUN_INSTALL_DIR" "install-only" "Install only"

  run ssm_run install-only "dev"

  assert_success
  assert_output --partial "OUTPUT:install-only"
}

@test "execute: user dir script runs when command exists only in user dir" {
  make_snippet "$_SSM_RUN_USER_DIR" "user-only" "User only"

  run ssm_run user-only "dev"

  assert_success
  assert_output --partial "OUTPUT:user-only"
}

@test "execute: user dir script takes precedence over install dir for same name" {
  # Install dir has a snippet that echoes INSTALL_VERSION
  mkdir -p "$_SSM_RUN_INSTALL_DIR"
  printf '# cmd\n# Shared\necho "INSTALL_VERSION"\n' > "$_SSM_RUN_INSTALL_DIR/shared"

  # User dir has a snippet that echoes USER_VERSION
  mkdir -p "$_SSM_RUN_USER_DIR"
  printf '# cmd\n# Shared\necho "USER_VERSION"\n' > "$_SSM_RUN_USER_DIR/shared"

  run ssm_run shared "dev"

  assert_success
  assert_output --partial "USER_VERSION"
  refute_output --partial "INSTALL_VERSION"
}

@test "execute: user dir executable script takes precedence over install dir snippet" {
  make_snippet "$_SSM_RUN_INSTALL_DIR" "myscript" "Install snippet"
  make_script  "$_SSM_RUN_USER_DIR"    "myscript" "User script"

  run ssm_run myscript

  assert_success
  assert_output --partial "OUTPUT:myscript"
  # Executable ran directly — no profile login
  refute_output --partial "LOGIN:"
}

# ── Exclusive override: -d flag ───────────────────────────────────────────────

@test "-d uses only the specified dir and ignores install dir" {
  make_snippet "$_SSM_RUN_INSTALL_DIR" "install-cmd" "Install command"
  local alt="$TEST_TMPDIR/alt"
  make_snippet "$alt" "alt-cmd" "Alt command"

  run ssm_run -d "$alt"

  assert_success
  assert_output --partial "alt-cmd"
  refute_output --partial "install-cmd"
}

@test "-d uses only the specified dir and ignores user dir" {
  make_snippet "$_SSM_RUN_USER_DIR" "user-cmd" "User command"
  local alt="$TEST_TMPDIR/alt"
  make_snippet "$alt" "alt-cmd" "Alt command"

  run ssm_run -d "$alt"

  assert_success
  assert_output --partial "alt-cmd"
  refute_output --partial "user-cmd"
}

@test "-d commands show no + marker even when script is user-authored" {
  local alt="$TEST_TMPDIR/alt"
  make_snippet "$alt" "alt-cmd" "Alt command"

  run ssm_run -d "$alt"

  assert_success
  assert_output --partial "alt-cmd"
  refute_output --partial "+"
}

@test "-d fails with error when specified dir does not exist" {
  run ssm_run -d "$TEST_TMPDIR/nonexistent"

  assert_failure
  assert_output --partial "Commands directory not found"
}

# ── Exclusive override: AWS_TOOLS_CMD_DIR ─────────────────────────────────────

@test "AWS_TOOLS_CMD_DIR uses only that dir and ignores install dir" {
  make_snippet "$_SSM_RUN_INSTALL_DIR" "install-cmd" "Install command"
  local override="$TEST_TMPDIR/override"
  make_snippet "$override" "override-cmd" "Override command"

  export AWS_TOOLS_CMD_DIR="$override"
  run ssm_run

  assert_success
  assert_output --partial "override-cmd"
  refute_output --partial "install-cmd"
}

@test "AWS_TOOLS_CMD_DIR uses only that dir and ignores user dir" {
  make_snippet "$_SSM_RUN_USER_DIR" "user-cmd" "User command"
  local override="$TEST_TMPDIR/override"
  make_snippet "$override" "override-cmd" "Override command"

  export AWS_TOOLS_CMD_DIR="$override"
  run ssm_run

  assert_success
  assert_output --partial "override-cmd"
  refute_output --partial "user-cmd"
}

@test "AWS_TOOLS_CMD_DIR commands show no + marker" {
  local override="$TEST_TMPDIR/override"
  make_snippet "$override" "override-cmd" "Override command"

  export AWS_TOOLS_CMD_DIR="$override"
  run ssm_run

  assert_success
  refute_output --partial "+"
}

@test "AWS_TOOLS_CMD_DIR fails with error when set to nonexistent dir" {
  export AWS_TOOLS_CMD_DIR="$TEST_TMPDIR/nonexistent"

  run ssm_run

  assert_failure
  assert_output --partial "Commands directory not found"
}

# ── Error cases ───────────────────────────────────────────────────────────────

@test "fails with error when neither install dir nor user dir exists" {
  # HOME is isolated with no dirs created — both default paths are missing
  run ssm_run

  assert_failure
  assert_output --partial "No run-commands directories found"
}

@test "list: shows 'No commands found' when dirs exist but are empty" {
  mkdir -p "$_SSM_RUN_INSTALL_DIR"

  run ssm_run

  assert_success
  assert_output --partial "No commands found"
}
