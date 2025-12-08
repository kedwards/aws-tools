# AWS SSM Tools - Unit Tests

This directory contains unit tests for the AWS SSM tools, specifically testing the `aws_ssm_connect_main` and `aws_ssm_execute_main` functions.

## Prerequisites

The tests use [Bats (Bash Automated Testing System)](https://github.com/bats-core/bats-core) for running unit tests on Bash scripts.

### Installing Bats

**On EndeavourOS/Arch Linux:**
```bash
sudo pacman -S bats
```

**On Ubuntu/Debian:**
```bash
sudo apt-get install bats
```

**On macOS (with Homebrew):**
```bash
brew install bats-core
```

**Or install from source:**
```bash
git clone https://github.com/bats-core/bats-core.git
cd bats-core
sudo ./install.sh /usr/local
```

## Running the Tests

### Run all tests
```bash
cd /home/kedwards/projects/aws-ssm-tools/connect-workflow
bats test/aws_ssm.bats
```

### Run a specific test
```bash
bats test/aws_ssm.bats --filter "prompts for profile and region"
```

### Run tests with verbose output
```bash
bats test/aws_ssm.bats --verbose-run
```

### Run tests with tap output (for CI/CD)
```bash
bats test/aws_ssm.bats --tap
```

## Test Coverage

The test suite covers the following scenarios:

### `aws_ssm_connect_main` Tests:
1. **Prompts for profile and region when AWS_PROFILE is unset** - Verifies that the function prompts the user to select an AWS profile and region when no profile is set in the environment.

2. **Handles no AWS profiles found gracefully** - Tests that the function returns an error when no AWS profiles are configured.

3. **Defaults to us-east-1 if no region is selected** - Ensures that when the user cancels region selection, the function defaults to `us-east-1`.

4. **Handles errors when assuming a selected profile** - Validates that the function properly handles and reports errors when profile assumption fails.

### `aws_ssm_execute_main` Tests:
5. **Correctly handles failures during profile assumption** - Tests error handling when the assume command fails during profile switching.

6. **Handles no AWS profiles found gracefully** - Verifies proper error handling when no AWS profiles exist.

7. **Defaults to us-east-1 if no region is selected when prompted** - Ensures region defaulting behavior works correctly for execute operations.

## Test Structure

Each test follows this pattern:

1. **Setup**: Creates a temporary HOME directory and mock AWS configuration
2. **Mock functions**: Overrides external dependencies (aws CLI, assume, menu functions)
3. **Execute**: Runs the function under test
4. **Assert**: Verifies expected behavior and return codes
5. **Teardown**: Cleans up temporary files and unsets environment variables

## Mocking Strategy

The tests mock the following external dependencies:
- `aws` CLI commands
- `assume` command (for profile switching)
- `menu_select_one` and `menu_select_multi` (for interactive selection)
- `aws_get_all_running_instances` (for instance listing)

This allows tests to run in isolation without requiring actual AWS credentials or infrastructure.

## Debugging Tests

To debug a failing test:

1. Add `set -x` at the beginning of the test to see command execution
2. Use `echo` statements to inspect variable values (output goes to stderr)
3. Check the test output for specific error messages
4. Run the test in isolation using the `--filter` option

## Contributing

When adding new functionality to the AWS SSM tools, please:

1. Add corresponding unit tests for new functions
2. Ensure all tests pass before submitting changes
3. Mock external dependencies appropriately
4. Follow the existing test structure and naming conventions
