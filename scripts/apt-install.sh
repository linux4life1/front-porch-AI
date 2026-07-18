#!/bin/bash
# Front Porch AI - APT Repository Installer
# Usage: curl -fsSL https://apt.frontporchai.app/install.sh | bash
set -euo pipefail

REPO_URL="https://apt.frontporchai.app"
KEYRING_PATH="/etc/apt/keyrings/front-porch-ai.gpg"
LIST_PATH="/etc/apt/sources.list.d/front-porch-ai.list"

echo "╔══════════════════════════════════════════════╗"
echo "║   Front Porch AI — APT Repository Setup      ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

# Check for root/sudo
if [ "$(id -u)" -ne 0 ]; then
    echo "This script requires sudo. Re-running with sudo..."
    exec sudo bash "$0" "$@"
fi

# Check if already installed
if [ -f "$LIST_PATH" ]; then
    echo "✓ Front Porch AI repository is already configured."
    echo "  Run: sudo apt update && sudo apt install front-porch-ai"
    exit 0
fi

echo "→ Downloading GPG signing key..."
mkdir -p /etc/apt/keyrings
curl -fsSL "${REPO_URL}/front-porch-ai.gpg" | gpg --dearmor -o "$KEYRING_PATH"

echo "→ Adding APT repository..."
echo "deb [signed-by=${KEYRING_PATH}] ${REPO_URL} stable main" > "$LIST_PATH"

echo "→ Updating package lists..."
apt update

echo ""
echo "✓ Repository added successfully!"
echo ""
echo "  Install:  sudo apt install front-porch-ai"
echo "  Update:   sudo apt update && sudo apt upgrade"
echo "  Remove:   sudo apt remove front-porch-ai"
echo ""
