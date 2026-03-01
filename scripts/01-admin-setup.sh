#!/bin/bash
# =============================================================================
# 01-admin-setup.sh — Run as the existing admin user on a fresh Mac Mini
#
# This script:
#   1. Enables FileVault (full-disk encryption)
#   2. Enables macOS firewall with stealth mode
#   3. Installs Homebrew (if not present)
#   4. Installs Tailscale
#   5. Creates a non-admin "openclaw" user account
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# --- Pre-flight checks -------------------------------------------------------

if [[ "$(uname)" != "Darwin" ]]; then
    error "This script must be run on macOS."
fi

# Check we're running as an admin user (but not root)
if [[ "$EUID" -eq 0 ]]; then
    error "Do not run this script as root. Run it as your admin user."
fi

if ! dscl . -read /Groups/admin GroupMembership 2>/dev/null | grep -qw "$(whoami)"; then
    error "Current user '$(whoami)' is not an admin. Run this from an admin account."
fi

echo ""
echo "=========================================="
echo "  OpenClaw Mac Mini — Admin Setup"
echo "=========================================="
echo ""

# --- 1. FileVault (Full-Disk Encryption) -------------------------------------

info "Checking FileVault status..."
fv_status=$(fdesetup status) || error "Failed to check FileVault status."

if echo "$fv_status" | grep -q "FileVault is On"; then
    info "FileVault is already enabled."
elif echo "$fv_status" | grep -q "Encryption in progress"; then
    info "FileVault encryption is in progress."
else
    warn "FileVault is not enabled. Enabling now..."
    warn "You will be prompted for your password. A recovery key will be displayed — SAVE IT."
    echo ""
    sudo fdesetup enable
    echo ""
    info "FileVault enabled. SAVE THE RECOVERY KEY shown above in your password manager."
fi

# --- 2. macOS Firewall --------------------------------------------------------

info "Checking firewall status..."
fw_status=$(sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate) || error "Failed to check firewall status."

if echo "$fw_status" | grep -q "enabled"; then
    info "Firewall is already enabled."
else
    warn "Firewall is not enabled. Enabling now..."
    sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on
    info "Firewall enabled."
fi

# Enable stealth mode (don't respond to pings or connection attempts)
stealth_status=$(sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getstealthmode) || error "Failed to check stealth mode status."
if echo "$stealth_status" | grep -q "enabled"; then
    info "Stealth mode is already enabled."
else
    sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode on
    info "Stealth mode enabled."
fi

# --- 3. Homebrew --------------------------------------------------------------

info "Checking for Homebrew..."
if ! command -v brew &>/dev/null && [[ ! -f /opt/homebrew/bin/brew ]] && [[ ! -f /usr/local/bin/brew ]]; then
    warn "Homebrew not found. Installing..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    info "Homebrew installed."
else
    info "Homebrew is already installed."
fi

# Ensure brew is on PATH for current session and future sessions
if [[ -f /opt/homebrew/bin/brew ]]; then
    BREW_BIN="/opt/homebrew/bin/brew"
elif [[ -f /usr/local/bin/brew ]]; then
    BREW_BIN="/usr/local/bin/brew"
else
    error "Homebrew binary not found at /opt/homebrew or /usr/local."
fi

eval "$("$BREW_BIN" shellenv)"

if ! grep -q 'brew shellenv' "$HOME/.zprofile" 2>/dev/null; then
    echo >> "$HOME/.zprofile"
    echo "eval \"\$(${BREW_BIN} shellenv)\"" >> "$HOME/.zprofile"
    info "Added Homebrew to PATH in ~/.zprofile"
fi

# --- 4. Tailscale -------------------------------------------------------------

info "Checking for Tailscale..."
if brew list --cask tailscale &>/dev/null 2>&1; then
    info "Tailscale is already installed."
else
    info "Installing Tailscale..."
    brew install --cask tailscale
    info "Tailscale installed."
fi

echo ""
warn "After this script completes, open Tailscale from Applications and log in."
warn "You can also run: open -a Tailscale"

# --- 5. Create 'openclaw' Standard User --------------------------------------

info "Checking for 'openclaw' user..."
if dscl . -read /Users/openclaw &>/dev/null 2>&1; then
    info "User 'openclaw' already exists."

    # Verify it's not an admin
    if dscl . -read /Groups/admin GroupMembership 2>/dev/null | grep -qw "openclaw"; then
        error "User 'openclaw' is an admin. For security, it must be a standard user. Remove it from the admin group first."
    else
        info "User 'openclaw' is a standard (non-admin) user. Good."
    fi
else
    info "Creating standard user 'openclaw'..."
    echo ""
    echo "Set a password for the 'openclaw' user:"
    read -rsp "> " openclaw_password
    echo ""
    echo "Confirm password:"
    read -rsp "> " openclaw_password_confirm
    echo ""

    if [[ "$openclaw_password" != "$openclaw_password_confirm" ]]; then
        error "Passwords do not match."
    fi
    if [[ -z "$openclaw_password" ]]; then
        error "Password cannot be empty."
    fi

    # Find an available UniqueID (macOS user IDs start at 501)
    last_id=$(dscl . -list /Users UniqueID | awk '{print $2}' | sort -n | tail -1)
    new_id=$((last_id + 1))

    sudo sysadminctl -addUser openclaw \
        -fullName "OpenClaw" \
        -shell /bin/zsh \
        -UID "$new_id" \
        -password "$openclaw_password"

    # Save password to the admin user's Keychain
    security add-generic-password \
        -a "$(whoami)" \
        -s "openclaw-user-password" \
        -l "OpenClaw macOS user password" \
        -w "$openclaw_password"
    info "Password saved to Keychain (service: openclaw-user-password)."

    # Clear the password from memory
    openclaw_password=""
    openclaw_password_confirm=""

    info "User 'openclaw' created as a standard (non-admin) user."
fi

# --- Summary ------------------------------------------------------------------

echo ""
echo "=========================================="
echo "  Admin Setup Complete"
echo "=========================================="
echo ""
info "Next steps:"
echo "  1. Open Tailscale and log in:  open -a Tailscale"
echo "  2. (Optional) Install dev tools:  bash scripts/01a-dev-setup.sh"
echo "  3. Switch to the openclaw user:  su - openclaw"
echo "  4. Run the OpenClaw setup script:  bash /path/to/scripts/02-openclaw-setup.sh"
echo "  5. Switch back to admin and install the daemon:  bash scripts/01b-install-daemon.sh"
echo ""
