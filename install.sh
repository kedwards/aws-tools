#!/usr/bin/env bash
set -euo pipefail

REPO_NAME="aws-ssm-tools"
REPO="kedwards/${REPO_NAME}"
INSTALL_DIR="${HOME}/.local/share/${REPO_NAME}"
BIN_DIR="${HOME}/.local/bin"
REPO_URL="https://github.com/${REPO}"

# Parse version argument (defaults to latest release or main if no releases exist)
VERSION="${1:-latest}"

echo "[INFO] Installing ${REPO_NAME} to ${INSTALL_DIR}"
mkdir -p "${INSTALL_DIR}"
mkdir -p "${BIN_DIR}"

# Determine download URL based on version
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

if [[ "$VERSION" == "latest" ]]; then
  # Try to get latest release tag, fallback to main
  echo "[INFO] Fetching latest release..."
  LATEST_TAG=$(curl -sSL "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' || echo "")
  
  if [[ -n "$LATEST_TAG" ]]; then
    echo "[INFO] Downloading ${REPO_NAME} ${LATEST_TAG}..."
    DOWNLOAD_URL="${REPO_URL}/archive/refs/tags/${LATEST_TAG}.tar.gz"
    EXTRACTED_DIR="${tmpdir}/${REPO_NAME}-${LATEST_TAG#v}"
  else
    echo "[INFO] No releases found, downloading from main branch..."
    DOWNLOAD_URL="${REPO_URL}/archive/refs/heads/main.tar.gz"
    EXTRACTED_DIR="${tmpdir}/${REPO_NAME}-main"
  fi
elif [[ "$VERSION" == "main" ]] || [[ "$VERSION" == "dev" ]]; then
  echo "[INFO] Downloading ${REPO_NAME} from main branch..."
  DOWNLOAD_URL="${REPO_URL}/archive/refs/heads/main.tar.gz"
  EXTRACTED_DIR="${tmpdir}/${REPO_NAME}-main"
else
  # Install specific version (tag)
  echo "[INFO] Downloading ${REPO_NAME} ${VERSION}..."
  DOWNLOAD_URL="${REPO_URL}/archive/refs/tags/${VERSION}.tar.gz"
  EXTRACTED_DIR="${tmpdir}/${REPO_NAME}-${VERSION#v}"
fi

curl -sSL "$DOWNLOAD_URL" | tar xz -C "$tmpdir"

# Sync files into installation directory
echo "[INFO] Copying files..."
rsync -a --delete "${EXTRACTED_DIR}/" "${INSTALL_DIR}/"

# Copy default commands from examples/commands.config to commands.config
if [[ -f "${INSTALL_DIR}/examples/commands.config" ]]; then
  echo "[INFO] Installing default commands..."
  cp "${INSTALL_DIR}/examples/commands.config" "${INSTALL_DIR}/commands.config"
else
  echo "[WARN] examples/commands.config not found, skipping default commands"
fi

# Copy default connections from examples/connections.config to connections.config
if [[ -f "${INSTALL_DIR}/examples/connections.config" ]]; then
  echo "[INFO] Installing default connections..."
  cp "${INSTALL_DIR}/examples/connections.config" "${INSTALL_DIR}/connections.config"
else
  echo "[WARN] examples/connections.config not found, skipping default connections"
fi

# Deploy default run-commands from examples/run-commands/
if [[ -d "${INSTALL_DIR}/examples/run-commands" ]]; then
  echo "[INFO] Installing default run-commands..."
  mkdir -p "${INSTALL_DIR}/run-commands"
  rsync -a --delete "${INSTALL_DIR}/examples/run-commands/" "${INSTALL_DIR}/run-commands/"
else
  echo "[WARN] examples/run-commands not found, skipping default run-commands"
fi

# Symlink the bin/ commands
echo "[INFO] Creating symlinks in ${BIN_DIR}"
for f in "${INSTALL_DIR}/bin/"*; do
  cmd="$(basename "$f")"
  ln -sf "${f}" "${BIN_DIR}/${cmd}"
done

# Note: Default configs are in INSTALL_DIR and will be loaded automatically
# Users can create custom configs in ~/.config/aws-ssm-tools/
echo "[INFO] Default commands available in ${INSTALL_DIR}/commands.config"
echo "[INFO] Default connections available in ${INSTALL_DIR}/connections.config"
echo "[INFO] Default run-commands available in ${INSTALL_DIR}/run-commands/"
echo "[INFO] Create custom commands in ~/.config/${REPO_NAME}/commands.user.config"
echo "[INFO] Create custom connections in ~/.config/${REPO_NAME}/connections.user.config"
echo "[INFO] Create custom run-commands in ~/.config/${REPO_NAME}/run-commands/"

# Show installed version
INSTALLED_VERSION="$(cat "${INSTALL_DIR}/VERSION" 2>/dev/null || echo 'unknown')"

echo ""
echo "[SUCCESS] ${REPO_NAME} v${INSTALLED_VERSION} installed!"
echo ""
echo "Ensure ~/.local/bin is in your PATH:"
echo ""
# shellcheck disable=SC2016
echo '  export PATH="$HOME/.local/bin:$PATH"'
echo ""
echo "Available commands:"
echo ""
echo "  ssm connect        # Connect to instances"
echo "  ssm exec           # Execute commands"
echo "  ssm list           # List active sessions"
echo "  ssm kill           # Kill active sessions"
echo ""
echo "Try:"
echo "  ssm --version"
echo "  ssm exec --help"
echo ""
echo "To install a specific version, run:"
echo "  ./install.sh v0.1.0"
echo ""

