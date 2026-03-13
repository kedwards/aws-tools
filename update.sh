#!/usr/bin/env bash
set -euo pipefail

REPO_NAME="aws-ssm-tools"
REPO="kedwards/${REPO_NAME}"
INSTALL_DIR="${HOME}/.local/share/${REPO_NAME}"
REPO_URL="https://github.com/${REPO}"

if [[ ! -d "${INSTALL_DIR}" ]]; then
  echo "[ERROR] ${REPO_NAME} is not installed in ${INSTALL_DIR}"
  echo "Install it with:"
  echo "  curl -sSL https://raw.githubusercontent.com/${REPO}/main/install.sh | bash"
  exit 1
fi

# Show current version
CURRENT_VERSION="$(cat "${INSTALL_DIR}/VERSION" 2>/dev/null || echo 'unknown')"
echo "[INFO] Current version: ${CURRENT_VERSION}"

# Parse version argument (defaults to latest release)
VERSION="${1:-latest}"

echo "[INFO] Updating ${REPO_NAME} in ${INSTALL_DIR}"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

# Determine download URL based on version
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
  # Update to specific version (tag)
  echo "[INFO] Downloading ${REPO_NAME} ${VERSION}..."
  DOWNLOAD_URL="${REPO_URL}/archive/refs/tags/${VERSION}.tar.gz"
  EXTRACTED_DIR="${tmpdir}/${REPO_NAME}-${VERSION#v}"
fi

curl -sSL "$DOWNLOAD_URL" | tar xz -C "$tmpdir"

echo "[INFO] Syncing files..."
rsync -a --delete "${EXTRACTED_DIR}/" "${INSTALL_DIR}/"

# Update default commands from examples/commands.config
if [[ -f "${INSTALL_DIR}/examples/commands.config" ]]; then
  echo "[INFO] Updating default commands..."
  cp "${INSTALL_DIR}/examples/commands.config" "${INSTALL_DIR}/commands.config"
else
  echo "[WARN] examples/commands.config not found, default commands may be outdated"
fi

# Update default connections from examples/connections.config
if [[ -f "${INSTALL_DIR}/examples/connections.config" ]]; then
  echo "[INFO] Updating default connections..."
  cp "${INSTALL_DIR}/examples/connections.config" "${INSTALL_DIR}/connections.config"
else
  echo "[WARN] examples/connections.config not found, default connections may be outdated"
fi

# Update default run-commands from examples/run-commands/
if [[ -d "${INSTALL_DIR}/examples/run-commands" ]]; then
  echo "[INFO] Updating default run-commands..."
  mkdir -p "${INSTALL_DIR}/run-commands"
  rsync -a --delete "${INSTALL_DIR}/examples/run-commands/" "${INSTALL_DIR}/run-commands/"
else
  echo "[WARN] examples/run-commands not found, default run-commands may be outdated"
fi

# User custom configs in ~/.config/aws-ssm-tools/ are preserved
echo "[INFO] Default commands updated in ${INSTALL_DIR}/commands.config"
echo "[INFO] Default connections updated in ${INSTALL_DIR}/connections.config"
echo "[INFO] Default run-commands updated in ${INSTALL_DIR}/run-commands/"
echo "[INFO] User custom commands preserved in ~/.config/${REPO_NAME}/commands.user.config"
echo "[INFO] User custom connections preserved in ~/.config/${REPO_NAME}/connections.user.config"
echo "[INFO] User run-commands preserved in ~/.config/${REPO_NAME}/run-commands/"

# Show new version
NEW_VERSION="$(cat "${INSTALL_DIR}/VERSION" 2>/dev/null || echo 'unknown')"

echo ""
if [[ "$CURRENT_VERSION" != "$NEW_VERSION" ]]; then
  echo "[SUCCESS] ${REPO_NAME} updated from v${CURRENT_VERSION} to v${NEW_VERSION}!"
else
  echo "[SUCCESS] ${REPO_NAME} v${NEW_VERSION} reinstalled!"
fi
echo ""
echo "To update to a specific version, run:"
echo "  ./update.sh v0.1.0"
echo ""
