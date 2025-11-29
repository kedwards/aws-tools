#!/usr/bin/env bash
set -euo pipefail

# Resolve repo root from any bin/* script
AWS_TOOLS_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"

# Make available to everything
export AWS_TOOLS_ROOT

# Load common libs
source "${AWS_TOOLS_ROOT}/lib/logging.sh"
source "${AWS_TOOLS_ROOT}/lib/menu.sh"
source "${AWS_TOOLS_ROOT}/lib/aws_profile.sh"
source "${AWS_TOOLS_ROOT}/lib/aws_instances.sh"
source "${AWS_TOOLS_ROOT}/lib/aws_ssm.sh"
source "${AWS_TOOLS_ROOT}/lib/aws_env_run.sh"
