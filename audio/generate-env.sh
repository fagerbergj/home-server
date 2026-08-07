#!/bin/bash
set -e
cd "$(dirname "$0")"

ENV_FILE="./.env"

touch "$ENV_FILE"
chmod 600 "$ENV_FILE"

echo "Nothing here is auto-generatable — HF_TOKEN is a Hugging Face credential."
echo
echo "Set by hand in $ENV_FILE:"
echo "  HF_TOKEN — https://huggingface.co/settings/tokens (see README.md)"
