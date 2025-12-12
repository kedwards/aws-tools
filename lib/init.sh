#!/usr/bin/env bash
set -eu

# Resolve repo root from any bin/* script
AWS_TOOLS_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"

# Make available to everything
export AWS_TOOLS_ROOT

# Load common libs in dependency order
source "${AWS_TOOLS_ROOT}/lib/logging.sh"
source "${AWS_TOOLS_ROOT}/lib/menu.sh"
source "${AWS_TOOLS_ROOT}/lib/aws_instances.sh"

# Check if modular libs exist (rewrite branch)
if [[ -f "${AWS_TOOLS_ROOT}/lib/common.sh" ]]; then
  source "${AWS_TOOLS_ROOT}/lib/common.sh"
  source "${AWS_TOOLS_ROOT}/lib/flags.sh"
  source "${AWS_TOOLS_ROOT}/lib/connect.sh"
  source "${AWS_TOOLS_ROOT}/lib/exec.sh"
  source "${AWS_TOOLS_ROOT}/lib/list.sh"
  source "${AWS_TOOLS_ROOT}/lib/kill.sh"
else
  # Fall back to monolithic lib (main branch)
  source "${AWS_TOOLS_ROOT}/lib/aws_ssm.sh"
fi

source "${AWS_TOOLS_ROOT}/lib/aws_env_run.sh"
