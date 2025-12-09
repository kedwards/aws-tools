#!/usr/bin/env bash
set -euo pipefail

REPO="kedwards/aws-ssm-tools"
INSTALL_DIR="${HOME}/.local/share/aws-ssm-tools"
REPO_URL="https://github.com/${REPO}"

if [[ ! -d "${INSTALL_DIR}" ]]; then
  echo "[ERROR] aws-ssm-tools is not installed in ${INSTALL_DIR}"
  echo "Install it with:"
  echo "  curl -sSL https://raw.githubusercontent.com/${REPO}/main/install.sh | bash"
  exit 1
fi

echo "[INFO] Updating aws-ssm-tools in ${INSTALL_DIR}"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

echo "[INFO] Downloading latest version..."
curl -sSL "${REPO_URL}/archive/refs/heads/main.tar.gz" |
  tar xz -C "$tmpdir"

EXTRACTED_DIR="${tmpdir}/aws-ssm-tools-main"

echo "[INFO] Syncing files..."
rsync -a --delete "${EXTRACTED_DIR}/" "${INSTALL_DIR}/"

# Default commands.config is automatically updated in INSTALL_DIR
# User custom commands in ~/.config/aws-ssm-tools/commands.user.config are preserved
echo "[INFO] Default commands updated in ${INSTALL_DIR}/commands.config"
echo "[INFO] User custom commands preserved in ~/.config/aws-ssm-tools/commands.user.config"

echo ""
echo "[SUCCESS] aws-ssm-tools updated!"
echo ""
