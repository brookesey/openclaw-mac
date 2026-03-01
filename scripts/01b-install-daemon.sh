#!/bin/bash
# =============================================================================
# 01b-install-daemon.sh — Run as admin, AFTER 02-openclaw-setup.sh
#
# This script:
#   1. Creates /var/log/openclaw/ for daemon logs
#   2. Copies the LaunchDaemon plist to /Library/LaunchDaemons/
#   3. Sets correct ownership and permissions
#   4. Loads the daemon so OpenClaw starts at boot
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

if [[ "$EUID" -eq 0 ]]; then
    error "Do not run this script as root. Run it as your admin user (sudo will be used where needed)."
fi

if ! dscl . -read /Groups/admin GroupMembership 2>/dev/null | grep -qw "$(whoami)"; then
    error "Current user '$(whoami)' is not an admin. Run this from an admin account."
fi

# Check that the openclaw user exists
if ! dscl . -read /Users/openclaw &>/dev/null 2>&1; then
    error "User 'openclaw' does not exist. Run 01-admin-setup.sh first."
fi

# Get the openclaw user's home directory
OPENCLAW_USER_HOME=$(dscl . -read /Users/openclaw NFSHomeDirectory 2>/dev/null | awk '{print $2}')
if [[ -z "$OPENCLAW_USER_HOME" ]]; then
    error "Could not determine home directory for 'openclaw' user."
fi

PLIST_SOURCE="$OPENCLAW_USER_HOME/.openclaw/ai.openclaw.gateway.plist"
PLIST_DEST="/Library/LaunchDaemons/ai.openclaw.gateway.plist"
LOG_DIR="/var/log/openclaw"

if ! sudo test -f "$PLIST_SOURCE"; then
    error "LaunchDaemon plist not found at $PLIST_SOURCE. Run 02-openclaw-setup.sh first."
fi

echo ""
echo "=========================================="
echo "  OpenClaw Mac Mini — Install Daemon"
echo "=========================================="
echo ""

# --- 1. Create log directory --------------------------------------------------

info "Creating log directory at $LOG_DIR..."
sudo mkdir -p "$LOG_DIR"
sudo chown openclaw:staff "$LOG_DIR"
sudo chmod 755 "$LOG_DIR"
info "Log directory ready."

# --- 2. Install the LaunchDaemon plist ----------------------------------------

info "Installing LaunchDaemon plist..."
sudo cp "$PLIST_SOURCE" "$PLIST_DEST"
sudo chown root:wheel "$PLIST_DEST"
sudo chmod 644 "$PLIST_DEST"
info "Plist installed at $PLIST_DEST"

# --- 3. Load the daemon -------------------------------------------------------

info "Loading the daemon..."

# Unload first if already loaded (ignore errors)
sudo launchctl bootout system/ai.openclaw.gateway 2>/dev/null || true

sudo launchctl bootstrap system "$PLIST_DEST"
info "Daemon loaded. OpenClaw gateway will now start at boot."

# --- 4. Verify it's running ---------------------------------------------------

sleep 2
if sudo launchctl print system/ai.openclaw.gateway &>/dev/null 2>&1; then
    info "Daemon is running."
else
    error "Daemon failed to start. Check logs at: $LOG_DIR/gateway.log and $LOG_DIR/gateway.err"
fi

# --- Summary ------------------------------------------------------------------

echo ""
echo "=========================================="
echo "  Daemon Installation Complete"
echo "=========================================="
echo ""
info "OpenClaw will now auto-start on boot and restart on crash."
echo ""
echo "  View logs:    tail -f $LOG_DIR/gateway.log"
echo "  View errors:  tail -f $LOG_DIR/gateway.err"
echo "  Stop daemon:  sudo launchctl bootout system/ai.openclaw.gateway"
echo "  Start daemon: sudo launchctl bootstrap system $PLIST_DEST"
echo ""
info "Next: run 03-verify.sh as the openclaw user to validate the setup."
echo ""
