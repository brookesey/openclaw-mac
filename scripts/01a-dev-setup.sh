#!/bin/bash
# =============================================================================
# 01a-dev-setup.sh — Run as the admin user, after 01-admin-setup.sh
#
# Installs development tools on the admin account:
#   1. GitHub CLI (gh)
#   2. Claude Code CLI
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# --- Pre-flight checks -------------------------------------------------------

if [[ "$(uname)" != "Darwin" ]]; then
    error "This script must be run on macOS."
fi

if ! command -v brew &>/dev/null; then
    error "Homebrew is not installed. Run 01-admin-setup.sh first."
fi

echo ""
echo "=========================================="
echo "  OpenClaw Mac Mini — Dev Environment"
echo "=========================================="
echo ""

# --- GitHub CLI ---------------------------------------------------------------

info "Checking for GitHub CLI..."
if command -v gh &>/dev/null; then
    info "GitHub CLI is already installed: $(gh --version | head -1)"
else
    info "Installing GitHub CLI..."
    brew install gh
    info "GitHub CLI installed: $(gh --version | head -1)"
fi

# --- Claude Code CLI ----------------------------------------------------------

# Ensure ~/.local/bin is on PATH (where Claude Code installs to)
if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    export PATH="$HOME/.local/bin:$PATH"
fi
if ! grep -q '.local/bin' "$HOME/.zprofile" 2>/dev/null; then
    echo >> "$HOME/.zprofile"
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.zprofile"
    info "Added ~/.local/bin to PATH in ~/.zprofile"
fi

info "Checking for Claude Code..."
if command -v claude &>/dev/null; then
    info "Claude Code is already installed: $(claude --version 2>/dev/null || echo 'installed')"
else
    info "Installing Claude Code..."
    curl -fsSL https://claude.ai/install.sh | bash
    info "Claude Code installed."
fi

# --- GitHub Auth --------------------------------------------------------------

echo ""
if gh auth status &>/dev/null 2>&1; then
    info "GitHub CLI is already authenticated."
else
    warn "GitHub CLI is not authenticated."
    read -rp "Run 'gh auth login' now? (Y/n): " do_auth
    if [[ ! "$do_auth" =~ ^[Nn]$ ]]; then
        gh auth login
    else
        info "Skipped. Run 'gh auth login' later to authenticate."
    fi
fi

# --- Summary ------------------------------------------------------------------

echo ""
echo "=========================================="
echo "  Dev Environment Setup Complete"
echo "=========================================="
echo ""
info "Installed:"
echo "  gh           $(gh --version 2>/dev/null | head -1 || echo 'not found')"
echo "  claude-code  $(claude --version 2>/dev/null || echo 'not found')"
echo ""
