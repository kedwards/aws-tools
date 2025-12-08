#!/usr/bin/env bats

# Load the script under test
setup() {
  # Source dependencies
  export AWS_LOG_LEVEL=ERROR  # Suppress logs during tests
  
  # Create temporary directory for test files
  TEST_TEMP_DIR="$(mktemp -d)"
  export HOME="$TEST_TEMP_DIR"
  
  # Source the libraries
  source "${BATS_TEST_DIRNAME}/../lib/logging.sh"
  source "${BATS_TEST_DIRNAME}/../lib/menu.sh"
  source "${BATS_TEST_DIRNAME}/../lib/aws_instances.sh"
  source "${BATS_TEST_DIRNAME}/../lib/aws_ssm.sh"
  
  # Mock external commands
  function aws() { echo "aws-mock"; }
  function assume() { return 0; }
  export -f aws assume
}

teardown() {
  # Clean up
  rm -rf "$TEST_TEMP_DIR"
  unset AWS_PROFILE
  unset AWS_REGION
}

# Test 1: aws_ssm_connect_main prompts for profile and region when AWS_PROFILE is unset
@test "aws_ssm_connect_main prompts for profile and region when AWS_PROFILE is unset" {
  # Setup: Create AWS config with profiles
  mkdir -p "$HOME/.aws"
  cat > "$HOME/.aws/config" <<EOF
[profile test-profile-1]
region = us-west-2

[profile test-profile-2]
region = us-east-1
EOF

  # Unset AWS_PROFILE to trigger prompting
  unset AWS_PROFILE
  
  # Mock menu_select_one to simulate user selections
  function menu_select_one() {
    local prompt="$1"
    local header="$2"
    local result_var="$3"
    shift 3
    
    # First call: profile selection
    if [[ "$prompt" == "Select AWS profile" ]]; then
      printf -v "$result_var" '%s' "test-profile-1"
      return 0
    # Second call: region selection
    elif [[ "$prompt" == "Select region for test-profile-1" ]]; then
      printf -v "$result_var" '%s' "us-west-2"
      return 0
    # Third call: instance selection
    elif [[ "$prompt" == "Select instance to connect to" ]]; then
      printf -v "$result_var" '%s' "test-instance i-123456"
      return 0
    fi
  }
  export -f menu_select_one
  
  # Mock aws_get_all_running_instances
  function aws_get_all_running_instances() {
    INSTANCE_LIST=("test-instance i-123456")
  }
  export -f aws_get_all_running_instances
  
  # Mock aws ssm start-session
  function aws() {
    if [[ "$1" == "ssm" && "$2" == "start-session" ]]; then
      echo "Session started"
      return 0
    fi
    echo "aws-mock"
  }
  export -f aws
  
  # Run the function
  run aws_ssm_connect_main
  
  # Verify it prompts and doesn't fail
  [ "$status" -eq 0 ]
}

# Test 2: aws_ssm_connect_main handles no AWS profiles found gracefully
@test "aws_ssm_connect_main handles no AWS profiles found gracefully" {
  # Setup: No AWS config file
  unset AWS_PROFILE
  
  # Ensure no .aws/config exists
  rm -rf "$HOME/.aws"
  
  # Run the function
  run aws_ssm_connect_main
  
  # Verify it returns error code 1
  [ "$status" -eq 1 ]
}

# Test 3: aws_ssm_connect_main defaults to us-east-1 if no region is selected when prompted
@test "aws_ssm_connect_main defaults to us-east-1 if no region is selected when prompted" {
  # Setup: Create AWS config with profiles
  mkdir -p "$HOME/.aws"
  cat > "$HOME/.aws/config" <<EOF
[profile test-profile]
region = us-west-2
EOF

  unset AWS_PROFILE
  
  # Track assume calls via file since arrays don't survive subshells
  ASSUME_CALLS_FILE="$TEST_TEMP_DIR/assume_calls.txt"
  export ASSUME_CALLS_FILE
  function assume() {
    echo "$@" >> "$ASSUME_CALLS_FILE"
    return 0
  }
  export -f assume
  
  # Mock menu_select_one to simulate profile selection and region cancellation
  function menu_select_one() {
    local prompt="$1"
    local header="$2"
    local result_var="$3"
    shift 3
    
    # First call: profile selection - succeed
    if [[ "$prompt" == "Select AWS profile" ]]; then
      printf -v "$result_var" '%s' "test-profile"
      return 0
    # Second call: region selection - return failure to simulate cancellation
    elif [[ "$prompt" == "Select region for test-profile" ]]; then
      return 1
    # Third call: instance selection
    elif [[ "$prompt" == "Select instance to connect to" ]]; then
      printf -v "$result_var" '%s' "test-instance i-123456"
      return 0
    fi
  }
  export -f menu_select_one
  
  # Mock aws_get_all_running_instances
  function aws_get_all_running_instances() {
    INSTANCE_LIST=("test-instance i-123456")
  }
  export -f aws_get_all_running_instances
  
  # Mock aws ssm start-session
  function aws() {
    if [[ "$1" == "ssm" && "$2" == "start-session" ]]; then
      echo "Session started"
      return 0
    fi
    echo "aws-mock"
  }
  export -f aws
  
  # Run the function
  run aws_ssm_connect_main
  
  # Verify it succeeds
  [ "$status" -eq 0 ]
  
  # Verify assume was called with us-east-1
  grep -q "us-east-1" "$ASSUME_CALLS_FILE"
}

# Test 4: aws_ssm_connect_main handles errors when assuming a selected profile
@test "aws_ssm_connect_main handles errors when assuming a selected profile" {
  # Setup: Create AWS config with profiles
  mkdir -p "$HOME/.aws"
  cat > "$HOME/.aws/config" <<EOF
[profile test-profile]
region = us-west-2
EOF

  unset AWS_PROFILE
  
  # Mock assume to fail
  function assume() {
    return 1
  }
  export -f assume
  
  # Mock menu_select_one to simulate user selections
  function menu_select_one() {
    local prompt="$1"
    local header="$2"
    local result_var="$3"
    shift 3
    
    # First call: profile selection
    if [[ "$prompt" == "Select AWS profile" ]]; then
      printf -v "$result_var" '%s' "test-profile"
      return 0
    # Second call: region selection
    elif [[ "$prompt" == "Select region for test-profile" ]]; then
      printf -v "$result_var" '%s' "us-west-2"
      return 0
    fi
  }
  export -f menu_select_one
  
  # Run the function
  run aws_ssm_connect_main
  
  # Verify it returns error code 1
  [ "$status" -eq 1 ]
}

# Test 5: aws_ssm_execute_main correctly handles failures during profile assumption
@test "aws_ssm_execute_main correctly handles failures during profile assumption" {
  # Setup: Create AWS config with profiles
  mkdir -p "$HOME/.aws"
  cat > "$HOME/.aws/config" <<EOF
[profile test-profile]
region = us-west-2
EOF

  unset AWS_PROFILE
  
  # Mock assume to fail
  function assume() {
    return 1
  }
  export -f assume
  
  # Mock menu_select_one to simulate user selections
  function menu_select_one() {
    local prompt="$1"
    local header="$2"
    local result_var="$3"
    shift 3
    
    # First call: profile selection
    if [[ "$prompt" == "Select AWS profile" ]]; then
      printf -v "$result_var" '%s' "test-profile"
      return 0
    # Second call: region selection
    elif [[ "$prompt" == "Select region for test-profile" ]]; then
      printf -v "$result_var" '%s' "us-west-2"
      return 0
    fi
  }
  export -f menu_select_one
  
  # Run the function with a command
  run aws_ssm_execute_main "echo test"
  
  # Verify it returns error code 1
  [ "$status" -eq 1 ]
}

# Additional test: Verify no profiles found in aws_ssm_execute_main
@test "aws_ssm_execute_main handles no AWS profiles found gracefully" {
  # Setup: No AWS config file
  unset AWS_PROFILE
  
  # Ensure no .aws/config exists
  rm -rf "$HOME/.aws"
  
  # Run the function with a command
  run aws_ssm_execute_main "echo test"
  
  # Verify it returns error code 1
  [ "$status" -eq 1 ]
}

# Additional test: Verify region defaults to us-east-1 in aws_ssm_execute_main
@test "aws_ssm_execute_main defaults to us-east-1 if no region is selected when prompted" {
  # Setup: Create AWS config with profiles
  mkdir -p "$HOME/.aws"
  cat > "$HOME/.aws/config" <<EOF
[profile test-profile]
region = us-west-2
EOF

  unset AWS_PROFILE
  
  # Track assume calls via file since arrays don't survive subshells
  ASSUME_CALLS_FILE="$TEST_TEMP_DIR/assume_calls.txt"
  export ASSUME_CALLS_FILE
  function assume() {
    echo "$@" >> "$ASSUME_CALLS_FILE"
    return 0
  }
  export -f assume
  
  # Mock menu_select_one to simulate profile selection and region cancellation
  function menu_select_one() {
    local prompt="$1"
    local header="$2"
    local result_var="$3"
    shift 3
    
    # First call: profile selection - succeed
    if [[ "$prompt" == "Select AWS profile" ]]; then
      printf -v "$result_var" '%s' "test-profile"
      return 0
    # Second call: region selection - return failure to simulate cancellation
    elif [[ "$prompt" == "Select region for test-profile" ]]; then
      return 1
    fi
  }
  export -f menu_select_one
  
  # Mock aws_get_all_running_instances
  function aws_get_all_running_instances() {
    INSTANCE_LIST=("test-instance i-123456")
  }
  export -f aws_get_all_running_instances
  
  # Mock menu_select_multi for instance selection
  function menu_select_multi() {
    local prompt="$1"
    local result_var="$2"
    shift 2
    declare -g "$result_var=test-instance i-123456"
    return 0
  }
  export -f menu_select_multi
  
  # Mock aws ssm send-command
  function aws() {
    if [[ "$1" == "ssm" && "$2" == "send-command" ]]; then
      echo "cmd-12345"
      return 0
    elif [[ "$1" == "ssm" && "$2" == "get-command-invocation" ]]; then
      if [[ "$*" =~ "--query Status" ]]; then
        echo "Success"
      else
        echo ""
      fi
      return 0
    fi
    echo "aws-mock"
  }
  export -f aws
  
  # Run the function with a command
  run aws_ssm_execute_main "echo test"
  
  # Verify it succeeds
  [ "$status" -eq 0 ]
  
  # Verify assume was called with us-east-1
  grep -q "us-east-1" "$ASSUME_CALLS_FILE"
}
