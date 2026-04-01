#!/bin/bash
# =============================================================================
# 01-admin-setup.sh — Run as the existing admin user on a fresh Mac Mini
#
# This script:
#   1. Enables FileVault (full-disk encryption)
#   2. Enables macOS firewall with stealth mode
#   3. Disables system sleep (server must stay awake for Telegram)
#   4. Installs Homebrew (if not present)
#   5. Installs Tailscale
#   6. Creates a non-admin "openclaw" user account
#   7. Copies scripts to a shared location accessible by all users
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARED_SCRIPTS_DIR="/usr/local/share/openclaw/scripts"

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

# --- 3. Disable System Sleep --------------------------------------------------

info "Disabling system sleep (server must stay awake for Telegram)..."
sudo pmset -a sleep 0 disablesleep 1
info "System sleep disabled. Display will still lock, but CPU and network stay active."

# --- 4. Homebrew --------------------------------------------------------------

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

# --- 5. Tailscale -------------------------------------------------------------

info "Checking for Tailscale..."
if brew list --cask tailscale &>/dev/null 2>&1 || [[ -f /usr/local/bin/tailscale ]]; then
    info "Tailscale is already installed."
else
    info "Installing Tailscale..."
    brew install --cask tailscale
    info "Tailscale installed."
fi

echo ""
warn "After this script completes, open Tailscale from Applications and log in."
warn "You can also run: open -a Tailscale"

# --- 6. Obsidian ---------------------------------------------------------------

info "Checking for Obsidian..."
if brew list --cask obsidian &>/dev/null 2>&1; then
    info "Obsidian is already installed."
else
    info "Installing Obsidian..."
    brew install --cask obsidian
    info "Obsidian installed."
fi

# --- 7. Create 'openclaw' Standard User --------------------------------------

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

# --- 8. Copy scripts to shared location ---------------------------------------

info "Copying scripts to $SHARED_SCRIPTS_DIR..."
sudo mkdir -p "$SHARED_SCRIPTS_DIR"
sudo cp -R "$SCRIPT_DIR/." "$SHARED_SCRIPTS_DIR/"

# Copy obsidian-vault template alongside scripts
SHARED_VAULT_DIR="/usr/local/share/openclaw/obsidian-vault"
REPO_VAULT_DIR="$SCRIPT_DIR/../obsidian-vault"
if [[ -d "$REPO_VAULT_DIR" ]]; then
    info "Copying Obsidian vault template to $SHARED_VAULT_DIR..."
    sudo mkdir -p "$SHARED_VAULT_DIR"
    sudo cp -R "$REPO_VAULT_DIR/." "$SHARED_VAULT_DIR/"
fi

sudo chown -R root:wheel /usr/local/share/openclaw
sudo find /usr/local/share/openclaw -type d -exec chmod 755 {} \;
sudo find /usr/local/share/openclaw -type f -exec chmod 644 {} \;
info "Scripts and templates copied to /usr/local/share/openclaw/"

# Grant admin user full access to openclaw's .openclaw directory via ACL
OPENCLAW_HOME=$(dscl . -read /Users/openclaw NFSHomeDirectory 2>/dev/null | awk '{print $2}')
ADMIN_USER="$(whoami)"
if [[ -n "$OPENCLAW_HOME" ]] && [[ -d "$OPENCLAW_HOME/.openclaw" ]]; then
    info "Granting $ADMIN_USER full access to $OPENCLAW_HOME/.openclaw/ via ACL..."
    sudo chmod +a "$ADMIN_USER allow read,write,execute,append,delete,readattr,writeattr,readextattr,writeextattr,readsecurity,list,search,add_file,add_subdirectory,delete_child,file_inherit,directory_inherit" "$OPENCLAW_HOME/.openclaw"
    info "ACL applied. Admin user '$ADMIN_USER' has full access to $OPENCLAW_HOME/.openclaw/"

    # Grant openclaw access to admin-owned files in the vault (e.g. from Obsidian Sync)
    VAULT_DIR="$OPENCLAW_HOME/.openclaw/workspace/obsidian-vault"
    if [[ -d "$VAULT_DIR" ]]; then
        info "Granting openclaw full access to vault (for files created by admin/Obsidian Sync)..."
        sudo chmod +a "openclaw allow read,write,execute,append,delete,readattr,writeattr,readextattr,writeextattr,readsecurity,list,search,add_file,add_subdirectory,delete_child,file_inherit,directory_inherit" "$VAULT_DIR"
        # Fix ownership of any existing admin-owned files
        sudo chown -R openclaw:staff "$VAULT_DIR"
        info "Vault ACL and ownership set."
    fi
else
    echo ""
    warn "$OPENCLAW_HOME/.openclaw/ does not exist yet."
    warn "After running 02-openclaw-setup.sh, re-run this script (or just the following command) to grant admin access:"
    warn "  sudo chmod +a \"$ADMIN_USER allow read,write,execute,append,delete,readattr,writeattr,readextattr,writeextattr,readsecurity,list,search,add_file,add_subdirectory,delete_child,file_inherit,directory_inherit\" $OPENCLAW_HOME/.openclaw"
fi

# Add a login reminder for the openclaw user
if [[ -n "$OPENCLAW_HOME" ]] && ! grep -q 'OpenClaw setup scripts' "$OPENCLAW_HOME/.zprofile" 2>/dev/null; then
    sudo tee -a "$OPENCLAW_HOME/.zprofile" > /dev/null <<'LOGINMSG'

# OpenClaw login reminder
echo ""
echo "OpenClaw setup scripts are at: /usr/local/share/openclaw/scripts/"
echo ""
LOGINMSG
    sudo chown openclaw:staff "$OPENCLAW_HOME/.zprofile"
    info "Added login reminder to openclaw user's ~/.zprofile"
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
echo "  3. Switch to the openclaw user:  sudo -u openclaw -i"
echo "  4. Run the OpenClaw setup script:  bash $SHARED_SCRIPTS_DIR/02-openclaw-setup.sh"
echo "  5. Switch back to admin and install the daemon:  bash scripts/01b-install-daemon.sh"
echo ""
