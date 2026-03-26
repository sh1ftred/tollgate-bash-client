#!/bin/bash

# TollGate Payment Script
# Usage: ./pay-internet.sh <cashu_token>
#
# Example: ./pay-internet.sh "cashuA..."

# TOLLGATE_HOST="172.19.217.1"
TOLLGATE_HOST="172.21.102.1"
PORT="${PORT:-2121}"
URL="http://${TOLLGATE_HOST}:${PORT}/"

# Function to get pricing info
get_pricing() {
    echo "=== TollGate Pricing Info ==="
    curl -s "${URL}" | jq '.' 2>/dev/null || curl -s "${URL}"
    echo
}

# Function to get your MAC address
get_whoami() {
    echo "=== Your MAC Address ==="
    curl -s "${URL}whoami"
    echo
    echo
}

# Function to check usage
get_usage() {
    echo "=== Your Usage ==="
    curl -s "${URL}usage"
    echo
    echo
}

# Function to pay with cashu token
pay() {
    local token="$1"
    if [ -z "$token" ]; then
        echo "Error: No cashu token provided"
        echo "Usage: $0 <cashu_token>"
        exit 1
    fi
    
    echo "=== Paying with Cashu Token ==="
    echo "Token length: ${#token} chars"
    echo
    
    # Send POST request with token
    response=$(curl -s -w "\n%{http_code}" -X POST \
        -H "Content-Type: text/plain" \
        -d "${token}" \
        "${URL}")
    
    # Extract HTTP status code (last line)
    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')
    
    echo "HTTP Status: ${http_code}"
    echo "Response:"
    echo "$body" | jq '.' 2>/dev/null || echo "$body"
}

# Main
case "${1:-}" in
    pricing|info)
        get_pricing
        ;;
    whoami)
        get_whoami
        ;;
    usage)
        get_usage
        ;;
    "")
        echo "TollGate Payment CLI"
        echo "===================="
        echo
        echo "Usage: $0 <command> [args]"
        echo
        echo "Commands:"
        echo "  pricing          - Get pricing info"
        echo "  whoami           - Get your MAC address"
        echo "  usage            - Check your usage"
        echo "  pay <token>      - Pay with a cashu token"
        echo
        echo "Examples:"
        echo "  $0 pricing"
        echo "  $0 whoami"
        echo "  $0 usage"
        echo "  $0 pay 'cashuA...'"
        echo
        echo "Environment variables:"
        echo "  TOLLGATE_HOST - TollGate IP (default: localhost)"
        echo "  PORT          - Port (default: 2121)"
        ;;
    pay)
        pay "${2:-}"
        ;;
    *)
        echo "Unknown command: $1"
        echo "Run '$0' without arguments for help"
        exit 1
        ;;
esac
