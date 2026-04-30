#!/bin/bash
# Phase 4 — Alerting for ZFS and disk-usage events.
#
# Wires up:
#   msmtp   — Gmail relay for all system mail (cron output, zed notifications).
#   ZED     — ZFS Event Daemon, emails on pool degraded / scrub failed / etc.
#   cron    — daily disk-usage check at 08:00 for /mnt/media and /mnt/personal.
#
# Gmail App Password can be provided via $GMAIL_APP_PASSWORD to run headless;
# otherwise the script prompts.
set -euo pipefail

cd "$(dirname "$0")"

EMAIL="jf.fagerberg@gmail.com"

# ---------------------------------------------------------------------------
# Install packages
# ---------------------------------------------------------------------------

echo "Installing msmtp and zfs-zed..."
sudo apt install -y msmtp msmtp-mta zfs-zed

# ---------------------------------------------------------------------------
# msmtp (Gmail relay)
# ---------------------------------------------------------------------------

if [[ -n "${GMAIL_APP_PASSWORD:-}" ]]; then
    PASSWORD="$GMAIL_APP_PASSWORD"
else
    echo ""
    echo "You'll need a Gmail App Password — not your regular password."
    echo "Generate one at: https://myaccount.google.com/apppasswords"
    echo "Tip: set GMAIL_APP_PASSWORD in your .env to skip this prompt."
    echo ""
    read -rsp "App password: " PASSWORD
    echo ""
fi

cat > ~/.msmtprc << EOF
defaults
auth           on
tls            on
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile        ~/.msmtp.log

account        gmail
host           smtp.gmail.com
port           587
from           $EMAIL
user           $EMAIL
password       $PASSWORD

account default : gmail
EOF
chmod 600 ~/.msmtprc
echo "msmtp configured."

# ---------------------------------------------------------------------------
# ZED — ZFS Event Daemon
# ---------------------------------------------------------------------------
#
# zed.rc is shipped by the zfs-zed package; we overwrite only the email-related
# knobs. Keeping the file complete (not appending) makes re-runs deterministic.

echo "Configuring ZED..."
sudo tee /etc/zfs/zed.d/zed.rc >/dev/null << EOF
# Managed by scripts/setup/phase4-alerts.sh
ZED_EMAIL_ADDR="$EMAIL"
ZED_EMAIL_PROG="msmtp"
ZED_EMAIL_OPTS="-a gmail @ADDRESS@"
ZED_NOTIFY_VERBOSE=1
ZED_NOTIFY_INTERVAL_SECS=3600
ZED_USE_ENCLOSURE_LEDS=1
ZED_SCRUB_AFTER_RESILVER=1
EOF

# On Ubuntu, `zed.service` is a systemd alias — must enable the real unit name.
sudo systemctl enable --now zfs-zed.service
echo "ZED enabled."

# ---------------------------------------------------------------------------
# Disk-usage cron (daily 08:00)
# ---------------------------------------------------------------------------

SCRIPT_PATH="$(realpath "$(dirname "$0")/../check-disk.sh")"
if ! { crontab -l 2>/dev/null || true; } | grep -q "check-disk.sh"; then
    ({ crontab -l 2>/dev/null || true; }; echo "0 8 * * * $SCRIPT_PATH") | crontab -
    echo "Disk usage check scheduled daily at 08:00 → $SCRIPT_PATH"
else
    echo "Disk usage cron job already exists — skipping."
fi

# ---------------------------------------------------------------------------
# Smoke test
# ---------------------------------------------------------------------------

echo ""
echo "Sending ZED test event (you should receive an email)..."
sudo zpool events -c || true   # clear zed's event history so the test isn't suppressed
# `zed -M` emits a "class=testing" event; harmless.
sudo zed -M 2>/dev/null || echo "(zed -M not supported in this zfs version — skipping)"

echo ""
echo "=== Alerts configured for $EMAIL ==="
