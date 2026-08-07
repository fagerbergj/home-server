#!/bin/bash
set -e
cd "$(dirname "$0")"

ENV_FILE="./.env"

touch "$ENV_FILE"
chmod 600 "$ENV_FILE"

echo "Nothing here is auto-generatable — all five values come from AirVPN."
echo
echo "Set by hand in $ENV_FILE (see setup.md):"
echo "  WIREGUARD_PRIVATE_KEY, WIREGUARD_PRESHARED_KEY, WIREGUARD_ADDRESSES"
echo "  AIRVPN_FORWARDED_PORT — airvpn.org > Client Area"
echo "  VPN_SERVER_COUNTRIES  — optional, defaults to Netherlands"
