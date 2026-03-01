# OpenClaw Mac Mini Setup

Automated, security-first setup for OpenClaw on a Mac Mini. Based on [this guide](https://stephenslee.medium.com/i-set-up-openclaw-on-a-mac-mini-with-security-as-priority-one-heres-exactly-how-050b7f625502), with Telegram as the messaging channel and Tailscale Serve for remote access.

## Prerequisites

- A Mac Mini (Apple Silicon or Intel)
- An admin macOS account (the default account created during initial setup)
- A [Tailscale](https://tailscale.com/) account
- An [Anthropic API key](https://console.anthropic.com/)
- A Telegram bot token (create one via [@BotFather](https://t.me/BotFather) on Telegram)

## Setup Steps

### Step 1: Admin Setup

Run from your admin account. This enables FileVault, the firewall, installs Homebrew + Tailscale, and creates a non-admin `openclaw` user.

```bash
bash scripts/01-admin-setup.sh
```

After this completes, open Tailscale and log in:

```bash
open -a Tailscale
```

### Step 1a: Dev Environment (Optional)

Still as admin, install development tools (GitHub CLI):

```bash
bash scripts/01a-dev-setup.sh
```

### Step 2: OpenClaw Setup

Switch to the `openclaw` user and run the setup script. This installs nvm, Node.js 22, OpenClaw, configures secrets, writes the config, and locks down permissions.

```bash
su - openclaw
bash /path/to/scripts/02-openclaw-setup.sh
```

You'll be prompted for:
- Your Anthropic API key
- Your Telegram bot token

### Step 3: Install the Daemon

Switch back to your admin account and install the LaunchDaemon so OpenClaw starts at boot.

```bash
exit  # back to admin
bash scripts/01b-install-daemon.sh
```

### Step 4: Verify

Switch to the `openclaw` user and run the verification script.

```bash
su - openclaw
bash /path/to/scripts/03-verify.sh
```

This checks every item from the security checklist and prints a pass/fail summary.

## Post-Setup

### Pairing Your Telegram Account

1. Send any message to your bot on Telegram
2. You'll see a pairing code in the OpenClaw logs
3. Approve it:

```bash
su - openclaw -c 'openclaw pairing approve telegram <CODE>'
```

### Edison's Personality

On your first interaction with the bot, send the contents of `scripts/personality.txt` to set Edison's personality and ground rules.

### Remote Access via Tailscale

The dashboard is accessible at `https://<your-machine-name>.<tailnet>/` from any device on your Tailscale network.

## Managing the Daemon

```bash
# View logs
tail -f /var/log/openclaw/gateway.log
tail -f /var/log/openclaw/gateway.err

# Stop
sudo launchctl bootout system/ai.openclaw.gateway

# Start
sudo launchctl bootstrap system /Library/LaunchDaemons/ai.openclaw.gateway.plist
```

## Security Checklist

- Latest version (>= 2026.1.29)
- Dedicated non-admin macOS user (`openclaw`)
- FileVault enabled
- macOS firewall on (stealth mode)
- Gateway bound to loopback (127.0.0.1)
- Token auth on gateway
- Tailscale Serve (tailnet-only, no Funnel)
- DMs set to pairing mode
- Claude Opus 4.6 (strongest prompt-injection resistance)
- Log redaction enabled
- Credentials in permissions-locked file (mode 600)
- No ClawHub skills installed
- `openclaw security audit --deep` run regularly
