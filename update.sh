#!/usr/bin/env bash
set -euo pipefail

REPO="kedwards/aws-tools"
INSTALL_DIR="${HOME}/.local/aws-tools"
REPO_URL="https://github.com/${REPO}"

if [[ ! -d "${INSTALL_DIR}" ]]; then
  echo "[ERROR] aws-tools is not installed in ${INSTALL_DIR}"
  echo "Install it with:"
  echo "  curl -sSL https://raw.githubusercontent.com/${REPO}/main/install.sh | bash"
  exit 1
fi

echo "[INFO] Updating aws-tools in ${INSTALL_DIR}"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

echo "[INFO] Downloading latest version..."
curl -sSL "${REPO_URL}/archive/refs/heads/main.tar.gz" |
  tar xz -C "$tmpdir"

EXTRACTED_DIR="${tmpdir}/aws-tools-main"

echo "[INFO] Syncing files..."
rsync -a --delete "${EXTRACTED_DIR}/" "${INSTALL_DIR}/"

echo ""
echo "[SUCCESS] aws-tools updated!"
echo ""
echo "Run:"
echo "  aws-profile --help"
