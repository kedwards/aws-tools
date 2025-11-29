#!/usr/bin/env bash
set -euo pipefail

REPO="kedwards/aws-tools"
INSTALL_DIR="${HOME}/.local/aws-tools"
BIN_DIR="${HOME}/.local/bin"

# Determine the repo root for downloads
REPO_URL="https://github.com/${REPO}"

echo "[INFO] Installing aws-tools to ${INSTALL_DIR}"
mkdir -p "${INSTALL_DIR}"
mkdir -p "${BIN_DIR}"

# Download latest main branch archive
echo "[INFO] Downloading aws-tools from GitHub..."
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

curl -sSL "${REPO_URL}/archive/refs/heads/main.tar.gz" |
  tar xz -C "$tmpdir"

# Extracted directory will be "aws-tools-main"
EXTRACTED_DIR="${tmpdir}/aws-tools-main"

# Sync files into installation directory
echo "[INFO] Copying files..."
rsync -a --delete "${EXTRACTED_DIR}/" "${INSTALL_DIR}/"

# Symlink the bin/ commands
echo "[INFO] Creating symlinks in ${BIN_DIR}"
for f in "${INSTALL_DIR}/bin/"*; do
  cmd="$(basename "$f")"
  ln -sf "${f}" "${BIN_DIR}/${cmd}"
done

echo ""
echo "[SUCCESS] aws-tools installed!"
echo ""
echo "Ensure ~/.local/bin is in your PATH:"
echo ""
echo '  export PATH="$HOME/.local/bin:$PATH"'
echo ""
echo "Try the commands:"
echo "  aws-profile --help"
echo "  aws-ssm-connect --help"
echo "  aws-ssm-exec --help"
echo ""
