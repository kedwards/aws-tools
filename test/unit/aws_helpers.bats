#!/usr/bin/env bats
# shellcheck disable=SC2034

export MENU_NON_INTERACTIVE=1
export AWST_EC2_DISABLE_LIVE_CALLS=1
export AWST_AUTH_DISABLE_ASSUME=1

setup() {
  # Stub logging
  log_debug() { :; }
  log_info() { :; }
  log_warn() { :; }
  log_error() { :; }
  export -f log_debug log_info log_warn log_error

  # Stub dependencies that aws.sh sources
  aws_get_all_running_instances() { :; }
  aws_expand_instances() { :; }
  awst_ssm_start_shell() { :; }
  awst_ssm_start_port_forward() { :; }
  menu_select_one() { :; }
  export -f aws_get_all_running_instances aws_expand_instances
  export -f awst_ssm_start_shell awst_ssm_start_port_forward menu_select_one

  # Set ROOT_DIR for sourcing
  ROOT_DIR="$(pwd)"
  export ROOT_DIR

  # Create temp directory for mock AWS config
  TEST_HOME="$(mktemp -d)"
  export HOME="$TEST_HOME"
  
  # Create mock .aws directory
  mkdir -p "$HOME/.aws"

  # Unset AWS environment variables to ensure tests are isolated
  unset AWS_PROFILE AWS_REGION AWS_DEFAULT_REGION
  unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
}

teardown() {
  # Clean up temp directory
  rm -rf "$TEST_HOME"
}

@test "aws_list_profiles returns empty when no config file" {
  source ./lib/core/aws.sh
  
  result=$(aws_list_profiles)
  [ -z "$result" ]
}

@test "aws_list_profiles parses single profile" {
  cat > "$HOME/.aws/config" <<EOF
[profile dev]
region = us-east-1
EOF

  source ./lib/core/aws.sh
  
  result=$(aws_list_profiles)
  [ "$result" = "dev" ]
}

@test "aws_list_profiles parses multiple profiles" {
  cat > "$HOME/.aws/config" <<EOF
[profile dev]
region = us-east-1

[profile staging]
region = us-west-2

[profile prod]
region = us-east-1
EOF

  source ./lib/core/aws.sh
  
  mapfile -t profiles < <(aws_list_profiles)
  [ "${#profiles[@]}" -eq 3 ]
  [ "${profiles[0]}" = "dev" ]
  [ "${profiles[1]}" = "staging" ]
  [ "${profiles[2]}" = "prod" ]
}

@test "aws_list_profiles handles default profile" {
  cat > "$HOME/.aws/config" <<EOF
[default]
region = us-east-1

[profile dev]
region = us-west-2
EOF

  source ./lib/core/aws.sh
  
  mapfile -t profiles < <(aws_list_profiles)
  [ "${#profiles[@]}" -eq 2 ]
  [ "${profiles[0]}" = "default" ]
  [ "${profiles[1]}" = "dev" ]
}

@test "aws_list_profiles ignores comments and blank lines" {
  cat > "$HOME/.aws/config" <<EOF
# This is a comment
[profile dev]
region = us-east-1

# Another comment
[profile prod]
region = us-west-2
EOF

  source ./lib/core/aws.sh
  
  mapfile -t profiles < <(aws_list_profiles)
  [ "${#profiles[@]}" -eq 2 ]
  [ "${profiles[0]}" = "dev" ]
  [ "${profiles[1]}" = "prod" ]
}

# awst_config_get tests

@test "awst_config_get returns empty for missing file" {
  source ./lib/core/aws.sh
  
  result=$(awst_config_get "/nonexistent" "section" "key")
  [ -z "$result" ]
}

@test "awst_config_get extracts value from INI section" {
  cat > "$HOME/test.ini" <<EOF
[db-conn]
port = 5432
host = localhost
EOF

  source ./lib/core/aws.sh
  
  result=$(awst_config_get "$HOME/test.ini" "db-conn" "port")
  [ "$result" = "5432" ]
}

@test "awst_config_get handles spaces around equals" {
  cat > "$HOME/test.ini" <<EOF
[db-conn]
port = 5432
host=localhost
region  =  us-east-1
EOF

  source ./lib/core/aws.sh
  
  port=$(awst_config_get "$HOME/test.ini" "db-conn" "port")
  host=$(awst_config_get "$HOME/test.ini" "db-conn" "host")
  region=$(awst_config_get "$HOME/test.ini" "db-conn" "region")
  
  [ "$port" = "5432" ]
  [ "$host" = "localhost" ]
  [ "$region" = "us-east-1" ]
}

@test "awst_config_get stops at next section" {
  cat > "$HOME/test.ini" <<EOF
[section1]
key1 = value1

[section2]
key1 = value2
key2 = value3
EOF

  source ./lib/core/aws.sh
  
  result1=$(awst_config_get "$HOME/test.ini" "section1" "key1")
  result2=$(awst_config_get "$HOME/test.ini" "section2" "key1")
  
  [ "$result1" = "value1" ]
  [ "$result2" = "value2" ]
}

@test "awst_config_get returns empty for missing key" {
  cat > "$HOME/test.ini" <<EOF
[db-conn]
port = 5432
EOF

  source ./lib/core/aws.sh
  
  result=$(awst_config_get "$HOME/test.ini" "db-conn" "missing")
  [ -z "$result" ]
}

@test "awst_config_get returns empty for missing section" {
  cat > "$HOME/test.ini" <<EOF
[db-conn]
port = 5432
EOF

  source ./lib/core/aws.sh
  
  result=$(awst_config_get "$HOME/test.ini" "missing-section" "port")
  [ -z "$result" ]
}

# choose_profile_and_region tests

@test "choose_profile_and_region uses aws_list_profiles" {
  cat > "$HOME/.aws/config" <<EOF
[profile test-profile]
region = us-west-2
EOF

  # Mock aws configure get
  aws() {
    if [[ "$1" == "configure" && "$2" == "get" ]]; then
      echo "us-west-2"
      return 0
    fi
    return 1
  }
  export -f aws

  # Set non-interactive to avoid menu
  export MENU_NON_INTERACTIVE=1
  PROFILE="test-profile"
  REGION=""

  source ./lib/core/aws.sh
  
  choose_profile_and_region
  [ "$PROFILE" = "test-profile" ]
  [ "$REGION" = "us-west-2" ]
}

@test "choose_profile_and_region detects region from sso_region" {
  cat > "$HOME/.aws/config" <<EOF
[profile sso-profile]
sso_region = us-east-1
EOF

  # Mock aws configure get - first call fails (no region), second succeeds (sso_region)
  aws() {
    if [[ "$1" == "configure" && "$2" == "get" ]]; then
      if [[ "$3" == "region" ]]; then
        return 1
      elif [[ "$3" =~ sso_region ]]; then
        echo "us-east-1"
        return 0
      fi
    fi
    return 1
  }
  export -f aws

  export MENU_NON_INTERACTIVE=1
  PROFILE="sso-profile"
  REGION=""

  source ./lib/core/aws.sh
  
  choose_profile_and_region
  [ "$REGION" = "us-east-1" ]
}

@test "choose_profile_and_region exports AWS_REGION" {
  cat > "$HOME/.aws/config" <<EOF
[profile test]
region = us-west-2
EOF

  aws() {
    if [[ "$1" == "configure" && "$2" == "get" ]]; then
      echo "us-west-2"
      return 0
    fi
    return 1
  }
  export -f aws

  export MENU_NON_INTERACTIVE=1
  PROFILE="test"
  REGION=""

  source ./lib/core/aws.sh
  
  choose_profile_and_region
  [ "$AWS_REGION" = "us-west-2" ]
  [ "$AWS_DEFAULT_REGION" = "us-west-2" ]
}

@test "choose_profile_and_region fails when profile required in non-interactive" {
  source ./lib/core/aws.sh
  
  export MENU_NON_INTERACTIVE=1
  PROFILE=""
  REGION=""

  run choose_profile_and_region
  [ "$status" -eq 1 ]
}

@test "choose_profile_and_region fails when region required in non-interactive" {
  cat > "$HOME/.aws/config" <<EOF
[profile test]
EOF

  aws() {
    return 1  # No region found
  }
  export -f aws

  source ./lib/core/aws.sh
  
  export MENU_NON_INTERACTIVE=1
  PROFILE="test"
  REGION=""

  run choose_profile_and_region
  [ "$status" -eq 1 ]
}

@test "choose_profile_and_region prompts for region even when auto-detected" {
  cat > "$HOME/.aws/config" <<EOF
[profile test]
region = us-east-1
EOF

  aws() {
    if [[ "$1" == "configure" && "$2" == "get" ]]; then
      echo "us-east-1"
      return 0
    fi
    return 1
  }
  export -f aws

  # Override menu_select_one to capture that it was called and what it received
  menu_select_one() {
    local prompt="$1"
    local __var="$3"
    shift 3
    # Verify detected region is listed first
    [[ "$1" == "us-east-1" ]] || return 1
    printf -v "$__var" '%s' "$1"
    return 0
  }
  export -f menu_select_one

  # Use interactive mode (MENU_NON_INTERACTIVE not set)
  unset MENU_NON_INTERACTIVE
  PROFILE="test"
  REGION=""

  source ./lib/core/aws.sh

  choose_profile_and_region
  [ "$REGION" = "us-east-1" ]
}

@test "choose_profile_and_region skips region menu when -r flag used" {
  cat > "$HOME/.aws/config" <<EOF
[profile test]
region = us-east-1
EOF

  aws() {
    if [[ "$1" == "configure" && "$2" == "get" ]]; then
      echo "us-east-1"
      return 0
    fi
    return 1
  }
  export -f aws

  local menu_called=false
  menu_select_one() {
    menu_called=true
    return 0
  }
  export -f menu_select_one

  unset MENU_NON_INTERACTIVE
  PROFILE="test"
  REGION="eu-west-1"  # simulates -r flag

  source ./lib/core/aws.sh

  choose_profile_and_region
  [ "$AWS_REGION" = "eu-west-1" ]
  [ "$menu_called" = false ]
}
