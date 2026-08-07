#!/bin/bash
set -e
cd "$(dirname "$0")"

ENV_FILE="./.env"

touch "$ENV_FILE"
chmod 600 "$ENV_FILE"

echo "Nothing here is auto-generatable — both values are tied to your DuckDNS account."
echo
echo "Set by hand in $ENV_FILE:"
echo "  DUCKDNS_SUBDOMAIN — the subdomain you claimed at https://www.duckdns.org"
echo "  DUCKDNS_TOKEN      — your DuckDNS account token"
