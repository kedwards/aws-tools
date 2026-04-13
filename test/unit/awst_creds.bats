#!/usr/bin/env bats
# shellcheck disable=SC2329,SC2030,SC2031

export MENU_NON_INTERACTIVE=1
export AWST_EC2_DISABLE_LIVE_CALLS=1
export AWST_AUTH_DISABLE_ASSUME=1

load '../helpers/bats-support/load'
load '../helpers/bats-assert/load'

# Stub logging
log_debug()   { :; }
log_info()    { echo "$*"; }
log_warn()    { :; }
log_error()   { echo "$*" >&2; }
log_success() { echo "$*"; }

setup() {
  # Isolate creds storage to a temp dir
  TEST_CREDS_DIR="$(mktemp -d)"
  export AWST_CREDS_DIR="$TEST_CREDS_DIR"

  source ./lib/commands/awst_creds.sh
}

teardown() {
  rm -rf "${TEST_CREDS_DIR:-}"
}

# --- usage ---

@test "awst_creds shows usage with no arguments" {
  run awst_creds

  assert_success
  assert_output --partial "Usage: awst creds <store|use|list|clear>"
  assert_output --partial "store <profile>"
  assert_output --partial "use [profile]"
  assert_output --partial "list"
  assert_output --partial "clear"
}

@test "awst_creds shows usage with unknown subcommand" {
  run awst_creds unknown

  assert_success
  assert_output --partial "Usage: awst creds <store|use|list|clear>"
}

@test "awst_creds shows usage with -h" {
  run awst_creds -h

  assert_success
  assert_output --partial "Usage: awst creds <store|use|list|clear>"
}

# --- store ---

@test "awst_creds store shows help with no profile" {
  run awst_creds store

  assert_success
  assert_output --partial "Usage: awst creds store <profile>"
  assert_output --partial "Requires: assume (Granted)"
}

@test "awst_creds store shows help with -h" {
  run awst_creds store -h

  assert_success
  assert_output --partial "Usage: awst creds store <profile>"
}

@test "awst_creds store shows help with --help" {
  run awst_creds store --help

  assert_success
  assert_output --partial "Usage: awst creds store <profile>"
}

@test "awst_creds store fails when assume not in PATH" {
  export AWST_AUTH_DISABLE_ASSUME=0

  command() {
    if [[ "$1" == "-v" && "$2" == "assume" ]]; then
      return 1
    fi
    builtin command "$@"
  }

  run awst_creds store myenv

  assert_failure
  assert_output --partial "'assume' (Granted) not found in PATH"
}

@test "awst_creds store skips when AWST_AUTH_DISABLE_ASSUME is set" {
  export AWST_AUTH_DISABLE_ASSUME=1

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

  run awst_creds store myenv

  assert_success
  refute_output --partial "SHOULD_NOT_RUN"
}

@test "awst_creds store persists credentials to per-profile file" {
  export AWST_AUTH_DISABLE_ASSUME=0

  command() {
    if [[ "$1" == "-v" && "$2" == "assume" ]]; then return 0; fi
    builtin command "$@"
  }

  assume() {
    cat <<'EOF'
AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE
AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
AWS_SESSION_TOKEN=FwoGZXIvYXdzEJr//////////wEaABC==
AWS_REGION=us-east-1
OTHER_VAR=should_be_ignored
EOF
  }

  run awst_creds store dev

  assert_success
  assert [ -f "$AWST_CREDS_DIR/dev.env" ]
}

@test "awst_creds store outputs eval-able exports" {
  export AWST_AUTH_DISABLE_ASSUME=0

  command() {
    if [[ "$1" == "-v" && "$2" == "assume" ]]; then return 0; fi
    builtin command "$@"
  }

  assume() {
    cat <<'EOF'
AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE
AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
AWS_SESSION_TOKEN=FwoGZXIvYXdzEJr//////////wEaABC==
AWS_REGION=us-east-1
EOF
  }

  run awst_creds store dev

  assert_success
  assert_output --partial 'export AWS_ACCESS_KEY_ID="AKIAIOSFODNN7EXAMPLE"'
  assert_output --partial 'export AWS_SECRET_ACCESS_KEY="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"'
  assert_output --partial 'export AWS_SESSION_TOKEN="FwoGZXIvYXdzEJr//////////wEaABC=="'
  assert_output --partial 'export AWS_REGION="us-east-1"'
  assert_output --partial 'export AWS_PROFILE="dev"'
  assert_output --partial 'export AK="AKIAIOSFODNN7EXAMPLE"'
}

@test "awst_creds store preserves session token with equals padding" {
  export AWST_AUTH_DISABLE_ASSUME=0

  command() {
    if [[ "$1" == "-v" && "$2" == "assume" ]]; then return 0; fi
    builtin command "$@"
  }

  assume() {
    echo "AWS_ACCESS_KEY_ID=AKIA"
    echo "AWS_SECRET_ACCESS_KEY=SECRET"
    echo "AWS_SESSION_TOKEN=base64token+with/padding=="
    echo "AWS_REGION=us-west-2"
  }

  run awst_creds store myprofile

  assert_success
  assert_output --partial 'export AWS_SESSION_TOKEN="base64token+with/padding=="'
}

@test "awst_creds store does not persist non-AWS vars" {
  export AWST_AUTH_DISABLE_ASSUME=0

  command() {
    if [[ "$1" == "-v" && "$2" == "assume" ]]; then return 0; fi
    builtin command "$@"
  }

  assume() {
    echo "AWS_ACCESS_KEY_ID=AKIA"
    echo "AWS_SECRET_ACCESS_KEY=SECRET"
    echo "AWS_SESSION_TOKEN=TOKEN"
    echo "AWS_REGION=us-east-1"
    echo "PATH=/usr/bin:/bin"
    echo "HOME=/home/user"
  }

  run awst_creds store dev
  assert_success

  run grep "PATH\|HOME" "$AWST_CREDS_DIR/dev.env"
  assert_failure
}

# --- use (no profile — backwards compat) ---

@test "awst_creds use with no profile outputs AK/SK/ST vars" {
  export AK="AKIATEST123"
  export SK="SECRET456"
  export ST="TOKEN789"

  run awst_creds use

  assert_success
  assert_output --partial 'export AWS_ACCESS_KEY_ID="AKIATEST123"'
  assert_output --partial 'AWS_SECRET_ACCESS_KEY="SECRET456"'
  assert_output --partial 'AWS_SESSION_TOKEN="TOKEN789"'
}

@test "awst_creds use with no profile outputs empty values when no stored vars" {
  unset AK SK ST

  run awst_creds use

  assert_success
  assert_output --partial 'AWS_ACCESS_KEY_ID=""'
  assert_output --partial 'AWS_SECRET_ACCESS_KEY=""'
  assert_output --partial 'AWS_SESSION_TOKEN=""'
}

# --- use <profile> ---

@test "awst_creds use with profile reads from creds file" {
  cat > "$AWST_CREDS_DIR/dev.env" <<'EOF'
AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE
AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
AWS_SESSION_TOKEN=FwoGZXIvYXdzEJr//////////wEaABC==
AWS_REGION=us-east-1
EOF

  run awst_creds use dev

  assert_success
  assert_output --partial 'export AWS_ACCESS_KEY_ID="AKIAIOSFODNN7EXAMPLE"'
  assert_output --partial 'export AWS_SECRET_ACCESS_KEY="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"'
  assert_output --partial 'export AWS_SESSION_TOKEN="FwoGZXIvYXdzEJr//////////wEaABC=="'
  assert_output --partial 'export AWS_REGION="us-east-1"'
  assert_output --partial 'export AWS_PROFILE="dev"'
}

@test "awst_creds use with profile preserves token equals padding" {
  cat > "$AWST_CREDS_DIR/prod.env" <<'EOF'
AWS_ACCESS_KEY_ID=AKIA
AWS_SECRET_ACCESS_KEY=SECRET
AWS_SESSION_TOKEN=base64token+with/padding==
AWS_REGION=us-west-2
EOF

  run awst_creds use prod

  assert_success
  assert_output --partial 'export AWS_SESSION_TOKEN="base64token+with/padding=="'
}

@test "awst_creds use fails for unknown profile" {
  run awst_creds use nonexistent

  assert_failure
  assert_output --partial "No stored credentials for profile 'nonexistent'"
  assert_output --partial "awst creds store nonexistent"
}

# --- list ---

@test "awst_creds list shows no credentials when dir is empty" {
  run awst_creds list

  assert_success
  assert_output --partial "No stored credentials found"
}

@test "awst_creds list shows no credentials when dir does not exist" {
  rm -rf "$AWST_CREDS_DIR"

  run awst_creds list

  assert_success
  assert_output --partial "No stored credentials found"
}

@test "awst_creds list shows stored profiles" {
  touch "$AWST_CREDS_DIR/dev.env"
  touch "$AWST_CREDS_DIR/prod.env"
  touch "$AWST_CREDS_DIR/staging.env"

  run awst_creds list

  assert_success
  assert_output --partial "dev"
  assert_output --partial "prod"
  assert_output --partial "staging"
}

# --- clear ---

@test "awst_creds clear removes specific profile" {
  touch "$AWST_CREDS_DIR/dev.env"
  touch "$AWST_CREDS_DIR/prod.env"

  run awst_creds clear dev

  assert_success
  assert [ ! -f "$AWST_CREDS_DIR/dev.env" ]
  assert [ -f "$AWST_CREDS_DIR/prod.env" ]
}

@test "awst_creds clear fails for unknown profile" {
  run awst_creds clear nonexistent

  assert_failure
  assert_output --partial "No stored credentials for profile 'nonexistent'"
}

@test "awst_creds clear with no profile removes all credentials" {
  touch "$AWST_CREDS_DIR/dev.env"
  touch "$AWST_CREDS_DIR/prod.env"
  touch "$AWST_CREDS_DIR/staging.env"

  run awst_creds clear

  assert_success
  assert [ ! -f "$AWST_CREDS_DIR/dev.env" ]
  assert [ ! -f "$AWST_CREDS_DIR/prod.env" ]
  assert [ ! -f "$AWST_CREDS_DIR/staging.env" ]
}

@test "awst_creds clear with no dir is a no-op" {
  rm -rf "$AWST_CREDS_DIR"

  run awst_creds clear

  assert_success
}

# --- dispatch ---

@test "awst_creds dispatches store subcommand" {
  awst_creds_store() {
    echo "STORE_CALLED: $*"
  }

  run awst_creds store myenv

  assert_success
  assert_output --partial "STORE_CALLED: myenv"
}

@test "awst_creds dispatches use subcommand" {
  awst_creds_use() {
    echo "USE_CALLED: $*"
  }

  run awst_creds use dev

  assert_success
  assert_output --partial "USE_CALLED: dev"
}

@test "awst_creds dispatches list subcommand" {
  awst_creds_list() {
    echo "LIST_CALLED"
  }

  run awst_creds list

  assert_success
  assert_output --partial "LIST_CALLED"
}

@test "awst_creds dispatches clear subcommand" {
  awst_creds_clear() {
    echo "CLEAR_CALLED: $*"
  }

  run awst_creds clear dev

  assert_success
  assert_output --partial "CLEAR_CALLED: dev"
}
