#!/bin/bash
# Configures msmtp for Gmail, mdadm failure alerts, and disk usage monitoring
set -euo pipefail

cd "$(dirname "$0")"

EMAIL="jf.fagerberg@gmail.com"

echo "Installing msmtp..."
sudo apt install -y msmtp msmtp-mta

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

# Add MAILADDR to mdadm.conf for RAID failure alerts
if ! grep -q "^MAILADDR" /etc/mdadm/mdadm.conf 2>/dev/null; then
    echo "MAILADDR $EMAIL" | sudo tee -a /etc/mdadm/mdadm.conf
    echo "Added MAILADDR to mdadm.conf."
else
    echo "MAILADDR already set in mdadm.conf — skipping."
fi

# Add disk usage cron job (runs daily at 8am)
SCRIPT_PATH="$(realpath "$(dirname "$0")/../check-disk.sh")"
if ! crontab -l 2>/dev/null | grep -q "check-disk.sh"; then
    (crontab -l 2>/dev/null; echo "0 8 * * * $SCRIPT_PATH") | crontab -
    echo "Disk usage check scheduled daily at 8am."
else
    echo "Disk usage cron job already exists — skipping."
fi

echo ""
echo "Testing mdadm alert (you should receive a test email)..."
sudo mdadm --monitor --scan --test --oneshot

echo ""
echo "=== Alerts configured for $EMAIL ==="
