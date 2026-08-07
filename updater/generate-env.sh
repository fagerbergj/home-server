#!/bin/bash
set -e
cd "$(dirname "$0")"

ENV_FILE="./.env"

touch "$ENV_FILE"
chmod 600 "$ENV_FILE"

echo "Nothing here is auto-generatable — GMAIL_APP_PASSWORD is a Google credential."
echo
echo "Set by hand in $ENV_FILE:"
echo "  GMAIL_APP_PASSWORD — https://myaccount.google.com/apppasswords"
