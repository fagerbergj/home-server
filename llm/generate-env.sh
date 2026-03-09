#!/bin/bash

set -e

if [ -f .env ]; then
    echo ".env already exists — delete it first if you want to regenerate"
    exit 1
fi

KEY=$(openssl rand -hex 32)
echo "OLLAMA_API_KEY=$KEY" > .env
echo "Generated .env with API key: $KEY"
