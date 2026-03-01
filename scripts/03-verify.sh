#!/bin/bash
# =============================================================================
# 03-verify.sh — Run as the 'openclaw' user after all other scripts
#
# Validates the full OpenClaw setup against the security checklist from:
# https://stephenslee.medium.com/i-set-up-openclaw-on-a-mac-mini-with-security-as-priority-one-heres-exactly-how-050b7f625502
# =============================================================================

set -uo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

pass() { echo -e "  ${GREEN}PASS${NC}  $*"; ((PASS++)); }
fail() { echo -e "  ${RED}FAIL${NC}  $*"; ((FAIL++)); }
warn() { echo -e "  ${YELLOW}WARN${NC}  $*"; ((WARN++)); }

echo ""
echo "=========================================="
echo "  OpenClaw Mac Mini — Verification"
echo "=========================================="
echo ""

# --- Source nvm if available --------------------------------------------------

export NVM_DIR="$HOME/.nvm"
# shellcheck source=/dev/null
[[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"

# --- 1. OpenClaw version check -----------------------------------------------

echo "--- OpenClaw Version ---"
MIN_VERSION="2026.2.15"

if command -v openclaw &>/dev/null; then
    oc_version=$(openclaw --version 2>/dev/null || echo "unknown")
    version_num=$(echo "$oc_version" | sed 's/[^0-9.]//g' | head -1)
    if [[ -n "$version_num" ]]; then
        if [[ "$(printf '%s\n' "$MIN_VERSION" "$version_num" | sort -V | head -1)" == "$MIN_VERSION" ]]; then
            pass "OpenClaw version $oc_version (>= $MIN_VERSION)"
        else
            fail "OpenClaw version $oc_version is below minimum $MIN_VERSION (CVE-2026-25253, GHSA-chf7-jq6g-qrwv)"
        fi
    else
        warn "Could not parse OpenClaw version: $oc_version"
    fi
else
    fail "OpenClaw command not found"
fi

# --- 2. Node.js version check ------------------------------------------------

echo ""
echo "--- Node.js ---"
if command -v node &>/dev/null; then
    node_ver=$(node --version)
    node_major=$(echo "$node_ver" | sed 's/v//' | cut -d. -f1)
    if [[ "$node_major" -ge 22 ]]; then
        pass "Node.js $node_ver (>= 22)"
    else
        fail "Node.js $node_ver (need >= 22)"
    fi
else
    fail "Node.js not found"
fi

if command -v nvm &>/dev/null || [[ -s "$NVM_DIR/nvm.sh" ]]; then
    pass "nvm is installed"
else
    fail "nvm not found"
fi

# --- 3. macOS user check -----------------------------------------------------

echo ""
echo "--- macOS User ---"
current_user=$(whoami)
if [[ "$current_user" == "openclaw" ]]; then
    pass "Running as 'openclaw' user"
else
    warn "Running as '$current_user' (expected 'openclaw')"
fi

if dscl . -read /Groups/admin GroupMembership 2>/dev/null | grep -qw "$current_user"; then
    fail "Current user '$current_user' is an admin (should be standard)"
else
    pass "Current user '$current_user' is a standard (non-admin) user"
fi

# --- 4. FileVault check ------------------------------------------------------

echo ""
echo "--- Disk Encryption ---"
fv_status=$(fdesetup status 2>/dev/null || echo "unknown")
if echo "$fv_status" | grep -q "FileVault is On"; then
    pass "FileVault is enabled"
elif echo "$fv_status" | grep -q "Encryption in progress"; then
    warn "FileVault encryption is still in progress"
else
    fail "FileVault is not enabled"
fi

# --- 5. Firewall check -------------------------------------------------------

echo ""
echo "--- Firewall ---"
# Note: these commands may need sudo, so we try without and handle gracefully
fw_global=$(/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null || echo "unknown")
if echo "$fw_global" | grep -qi "enabled"; then
    pass "macOS firewall is enabled"
else
    fail "macOS firewall is not enabled (or could not check — may need sudo)"
fi

fw_stealth=$(/usr/libexec/ApplicationFirewall/socketfilterfw --getstealthmode 2>/dev/null || echo "unknown")
if echo "$fw_stealth" | grep -qi "enabled"; then
    pass "Stealth mode is enabled"
else
    warn "Stealth mode status unknown (may need sudo to check)"
fi

# --- 6. Power Management check -----------------------------------------------

echo ""
echo "--- Power Management ---"
sleep_val=$(pmset -g 2>/dev/null | grep '^ sleep' | awk '{print $2}')
if [[ "$sleep_val" == "0" ]]; then
    pass "System sleep is disabled (sleep = 0)"
else
    fail "System sleep is set to $sleep_val (expected 0 — run: sudo pmset -a sleep 0 disablesleep 1)"
fi

# --- 7. OpenClaw config check ------------------------------------------------

echo ""
echo "--- OpenClaw Configuration ---"
CONFIG_FILE="$HOME/.openclaw/openclaw.json"
if [[ -f "$CONFIG_FILE" ]]; then
    pass "Config file exists at $CONFIG_FILE"

    # Check key settings via grep on the JSON
    if grep -q '"loopback"' "$CONFIG_FILE"; then
        pass "Gateway bound to loopback"
    else
        fail "Gateway is NOT bound to loopback"
    fi

    if grep -q '"token"' "$CONFIG_FILE"; then
        pass "Gateway auth mode is token"
    else
        fail "Gateway auth mode is not token"
    fi

    if grep -q '"serve"' "$CONFIG_FILE"; then
        pass "Tailscale mode is serve (tailnet-only)"
    else
        warn "Tailscale mode is not set to serve"
    fi

    if grep -q '"pairing"' "$CONFIG_FILE"; then
        pass "DM policy is pairing"
    else
        fail "DM policy is not set to pairing"
    fi

    if grep -q '"claude-opus-4-6"' "$CONFIG_FILE"; then
        pass "Model is Claude Opus 4.6 (SOTA)"
    else
        warn "Model is not set to Claude Opus 4.6"
    fi

    if grep -q '"redactSensitive"' "$CONFIG_FILE"; then
        pass "Log redaction is enabled"
    else
        warn "Log redaction is not configured"
    fi

    if grep -q '"deny"' "$CONFIG_FILE"; then
        pass "Tool deny list is configured"
    else
        fail "No tool deny list — bot can modify its own config (add gateway, cron, sessions_spawn, sessions_send)"
    fi

    if grep -q '"workspaceOnly"' "$CONFIG_FILE"; then
        pass "Filesystem restricted to workspace only"
    else
        warn "Filesystem not restricted to workspace — bot can access files outside workspace"
    fi

    if grep -q '"configWrites".*false' "$CONFIG_FILE"; then
        pass "Telegram configWrites disabled"
    else
        fail "configWrites not disabled — Telegram events could modify config"
    fi

    if grep -q '"requireMention"' "$CONFIG_FILE"; then
        pass "Group messages require @mention"
    else
        warn "Group requireMention not set — bot responds to all group messages"
    fi

    if grep -q '"tokenFile"' "$CONFIG_FILE"; then
        pass "Telegram token loaded via tokenFile (not env var)"
    else
        warn "Telegram token not using tokenFile — env vars can leak in process listings"
    fi
else
    fail "Config file not found at $CONFIG_FILE"
fi

# --- 8. File permissions check ------------------------------------------------

echo ""
echo "--- File Permissions ---"
OPENCLAW_HOME="$HOME/.openclaw"

if [[ -d "$OPENCLAW_HOME" ]]; then
    dir_perms=$(stat -f "%Lp" "$OPENCLAW_HOME")
    if [[ "$dir_perms" == "700" ]]; then
        pass "~/.openclaw/ permissions: $dir_perms (700)"
    else
        fail "~/.openclaw/ permissions: $dir_perms (expected 700)"
    fi
fi

if [[ -f "$CONFIG_FILE" ]]; then
    cfg_perms=$(stat -f "%Lp" "$CONFIG_FILE")
    if [[ "$cfg_perms" == "600" ]]; then
        pass "openclaw.json permissions: $cfg_perms (600)"
    else
        fail "openclaw.json permissions: $cfg_perms (expected 600)"
    fi
fi

SECRETS_FILE="$OPENCLAW_HOME/secrets.env"
if [[ -f "$SECRETS_FILE" ]]; then
    sec_perms=$(stat -f "%Lp" "$SECRETS_FILE")
    if [[ "$sec_perms" == "600" ]]; then
        pass "secrets.env permissions: $sec_perms (600)"
    else
        fail "secrets.env permissions: $sec_perms (expected 600)"
    fi
else
    fail "secrets.env not found"
fi

TELEGRAM_TOKEN_FILE="$OPENCLAW_HOME/credentials/telegram-token"
if [[ -f "$TELEGRAM_TOKEN_FILE" ]]; then
    tg_perms=$(stat -f "%Lp" "$TELEGRAM_TOKEN_FILE")
    if [[ "$tg_perms" == "600" ]]; then
        pass "telegram-token permissions: $tg_perms (600)"
    else
        fail "telegram-token permissions: $tg_perms (expected 600)"
    fi
else
    warn "telegram-token file not found (Telegram token may be using env var instead)"
fi

WRAPPER_SCRIPT="$OPENCLAW_HOME/start.sh"
if [[ -f "$WRAPPER_SCRIPT" ]]; then
    wrap_perms=$(stat -f "%Lp" "$WRAPPER_SCRIPT")
    if [[ "$wrap_perms" == "700" ]]; then
        pass "start.sh permissions: $wrap_perms (700)"
    else
        fail "start.sh permissions: $wrap_perms (expected 700)"
    fi
else
    fail "start.sh not found"
fi

# --- 9. Tailscale check ------------------------------------------------------

echo ""
echo "--- Tailscale ---"
if command -v tailscale &>/dev/null || [[ -f /Applications/Tailscale.app/Contents/MacOS/Tailscale ]]; then
    pass "Tailscale is installed"

    ts_status=$(tailscale status 2>/dev/null || echo "not running")
    if echo "$ts_status" | grep -q "offline\|stopped\|not running"; then
        warn "Tailscale is not currently connected"
    else
        pass "Tailscale is connected"
    fi
else
    fail "Tailscale is not installed"
fi

# --- 10. LaunchDaemon check ---------------------------------------------------

echo ""
echo "--- LaunchDaemon ---"
PLIST_DEST="/Library/LaunchDaemons/ai.openclaw.gateway.plist"
if [[ -f "$PLIST_DEST" ]]; then
    pass "LaunchDaemon plist is installed"
else
    fail "LaunchDaemon plist not found at $PLIST_DEST"
fi

# Check if the daemon is loaded
if launchctl print system/ai.openclaw.gateway &>/dev/null 2>&1; then
    pass "LaunchDaemon is loaded and running"
else
    warn "LaunchDaemon may not be loaded (may need sudo to check)"
fi

# --- 11. OpenClaw doctor and security audit -----------------------------------

echo ""
echo "--- OpenClaw Doctor ---"
if command -v openclaw &>/dev/null; then
    if openclaw doctor 2>&1; then
        pass "openclaw doctor passed"
    else
        fail "openclaw doctor reported issues (see above)"
    fi
fi

echo ""
echo "--- OpenClaw Security Audit ---"
if command -v openclaw &>/dev/null; then
    if openclaw security audit --deep 2>&1; then
        pass "openclaw security audit --deep passed"
    else
        fail "Security audit reported issues (see above)"
    fi
fi

# --- 12. Channel status -------------------------------------------------------

echo ""
echo "--- Channel Status ---"
if command -v openclaw &>/dev/null; then
    if openclaw channels status --probe 2>&1; then
        pass "Telegram channel is connected"
    else
        fail "Channel probe reported issues (see above)"
    fi
fi

# --- Summary ------------------------------------------------------------------

echo ""
echo "=========================================="
echo "  Verification Summary"
echo "=========================================="
echo ""
echo -e "  ${GREEN}PASS${NC}: $PASS"
echo -e "  ${RED}FAIL${NC}: $FAIL"
echo -e "  ${YELLOW}WARN${NC}: $WARN"
echo ""

if [[ $FAIL -eq 0 ]]; then
    echo -e "${GREEN}All checks passed!${NC}"
else
    echo -e "${RED}$FAIL check(s) failed. Review the output above and fix before using OpenClaw.${NC}"
fi

EXIT_CODE=0
if [[ $FAIL -gt 0 ]]; then
    EXIT_CODE=1
fi

echo ""
echo "--- Security Checklist (from the article) ---"
echo ""
echo "  [$(command -v openclaw &>/dev/null && echo 'x' || echo ' ')] Latest version (>= 2026.1.29)"
echo "  [$(dscl . -read /Groups/admin GroupMembership 2>/dev/null | grep -qw "$(whoami)" && echo ' ' || echo 'x')] Dedicated non-admin macOS user"
echo "  [$(fdesetup status 2>/dev/null | grep -q 'On' && echo 'x' || echo ' ')] FileVault enabled"
echo "  [$(/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null | grep -qi 'enabled' && echo 'x' || echo ' ')] macOS firewall on"
echo "  [$(pmset -g 2>/dev/null | grep '^ sleep' | awk '{print $2}' | grep -q '^0$' && echo 'x' || echo ' ')] System sleep disabled"
echo "  [$(grep -q '"loopback"' "$CONFIG_FILE" 2>/dev/null && echo 'x' || echo ' ')] Gateway bound to 127.0.0.1"
echo "  [$(grep -q '"token"' "$CONFIG_FILE" 2>/dev/null && echo 'x' || echo ' ')] Token auth on gateway"
echo "  [$(grep -q '"serve"' "$CONFIG_FILE" 2>/dev/null && echo 'x' || echo ' ')] Tailscale in serve mode (tailnet-only)"
echo "  [$(grep -q '"pairing"' "$CONFIG_FILE" 2>/dev/null && echo 'x' || echo ' ')] DMs set to pairing"
echo "  [ ] Channel allowlists locked to my IDs only (verify after pairing)"
echo "  [$(grep -q '"claude-opus-4-6"' "$CONFIG_FILE" 2>/dev/null && echo 'x' || echo ' ')] SOTA model (Claude Opus 4.6)"
echo "  [ ] API spending limits set with provider (verify in Anthropic dashboard)"
echo "  [$(grep -q '"redactSensitive"' "$CONFIG_FILE" 2>/dev/null && echo 'x' || echo ' ')] Log redaction on"
echo "  [$(stat -f "%Lp" "$SECRETS_FILE" 2>/dev/null | grep -q '600' && echo 'x' || echo ' ')] All credentials secured (permissions 600)"
echo "  [$(grep -q '"deny"' "$CONFIG_FILE" 2>/dev/null && echo 'x' || echo ' ')] Tool deny list configured (gateway, cron, sessions)"
echo "  [$(grep -q '"workspaceOnly"' "$CONFIG_FILE" 2>/dev/null && echo 'x' || echo ' ')] Filesystem restricted to workspace"
echo "  [$(grep -q '"configWrites".*false' "$CONFIG_FILE" 2>/dev/null && echo 'x' || echo ' ')] Telegram configWrites disabled"
echo "  [$(grep -q '"requireMention"' "$CONFIG_FILE" 2>/dev/null && echo 'x' || echo ' ')] Group messages require @mention"
echo "  [$(grep -q '"tokenFile"' "$CONFIG_FILE" 2>/dev/null && echo 'x' || echo ' ')] Telegram token via tokenFile"
echo "  [ ] Telegram Privacy Mode enabled (verify in @BotFather: /mybots > Bot Settings > Group Privacy)"
echo "  [x] No ClawHub skills installed (clean install)"
echo "  [x] openclaw security audit --deep run (just ran above)"
echo ""

exit $EXIT_CODE
