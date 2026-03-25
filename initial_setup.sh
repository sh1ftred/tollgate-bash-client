#!/bin/bash
# Generate initial offline token from cocod

OFFLINE_TOKENS_FILE="offline_cashu.txt"

echo "Generating Cashu token..."
token=$(cocod send cashu 1)

if [ -z "$token" ]; then
    echo "Failed to generate token"
    exit 1
fi

echo "$token" >> "$OFFLINE_TOKENS_FILE"
echo "Added token to stash. Stash now has $(wc -l < "$OFFLINE_TOKENS_FILE" | tr -d ' ') tokens."
