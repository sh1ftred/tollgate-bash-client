#!/bin/bash
# Auto-pay internet with usage tracking
# Uses offline tokens first, refills stash after each successful payment

TOLLGATE_HOST="172.19.217.1"
PORT="2121"
URL="http://${TOLLGATE_HOST}:${PORT}"
INTERVAL=2
TOPUP_THRESHOLD_MB=5
OFFLINE_TOKENS_FILE="offline_cashu.txt"

# Get pricing info
get_pricing() {
    curl -s "${URL}" | jq '{
        step_size: (.tags[] | select(.[0] == "step_size") | .[1] | tonumber),
        price_per_step: (.tags[] | select(.[0] == "price_per_step") | .[2] | tonumber)
    }'
}

# Get local bytes on en0
get_local_bytes() {
    netstat -ib | grep -E '^en0' | awk '{print $7, $10}'
}

# Pay with cashu token
pay() {
    local token="$1"
    curl -s -X POST -H "Content-Type: text/plain" -d "$token" "${URL}"
}

# Check if payment failed (spent token)
payment_failed() {
    local result="$1"
    echo "$result" | jq -r '.content' 2>/dev/null | grep -q "already spent"
}

# Get next offline token
get_offline_token() {
    if [ ! -f "$OFFLINE_TOKENS_FILE" ]; then
        echo ""
        return
    fi
    
    local token=$(head -1 "$OFFLINE_TOKENS_FILE")
    if [ -z "$token" ]; then
        echo ""
        return
    fi
    
    # Remove used token from file
    tail -n +2 "$OFFLINE_TOKENS_FILE" > "${OFFLINE_TOKENS_FILE}.tmp"
    mv "${OFFLINE_TOKENS_FILE}.tmp" "$OFFLINE_TOKENS_FILE"
    
    echo "$token"
}

# Count remaining offline tokens
count_offline_tokens() {
    if [ -f "$OFFLINE_TOKENS_FILE" ]; then
        wc -l < "$OFFLINE_TOKENS_FILE" | tr -d ' '
    else
        echo "0"
    fi
}

# Refill offline stash with new token from cocod
refill_stash() {
    echo "Refilling offline stash..."
    token=$(cocod send cashu 1)
    echo "$token" >> "$OFFLINE_TOKENS_FILE"
    echo "Stash refilled. Now $(count_offline_tokens) tokens."
}

# Try to pay with a token, retry if spent
try_pay() {
    local token="$1"
    echo "Token: ${token:0:50}..."
    result=$(pay "$token")
    
    if payment_failed "$result"; then
        echo "Token already spent, trying next..."
        return 1
    fi
    
    echo "Paid."
    return 0
}

# Do payment
do_pay() {
    local offline_count=$(count_offline_tokens)
    local token=""
    
    # Try up to 3 tokens (offline or cocod)
    for i in 1 2 3; do
        if [ "$offline_count" -gt 0 ]; then
            echo "Using offline token ($offline_count remaining)..."
            token=$(get_offline_token)
        else
            echo "Generating via cocod..."
            token=$(cocod send cashu 1)
        fi
        
        if try_pay "$token"; then
            # Success - refill stash
            refill_stash
            return 0
        fi
        
        # Token was spent, update count and retry
        offline_count=$(count_offline_tokens)
        
        # If no more offline tokens and last attempt was cocod, try cocod again
        if [ "$offline_count" -eq 0 ] && [ "$i" -eq 1 ]; then
            : # will try cocod again on next loop iteration
        fi
    done
    
    echo "ERROR: All tokens failed"
    return 1
}

# Get current usage (extract just the numbers line)
get_usage() {
    local usage=$(./pay-internet.sh usage 2>/dev/null | grep '/' | head -1)
    if [ -z "$usage" ]; then
        echo "0/0"
    else
        echo "$usage"
    fi
}

echo "=== Auto-Pay Internet ==="

# Fetch pricing
pricing=$(get_pricing)
bytes_per_sat=$(echo "$pricing" | jq -r '.step_size')
echo "Pricing: 1 sat = $bytes_per_sat bytes ($((bytes_per_sat/1048576)) MB)"

# Fetch initial usage
usage=$(get_usage)
allocated=$(echo "$usage" | cut -d'/' -f2)
used=$(echo "$usage" | cut -d'/' -f1)

echo "Usage: $((used/1048576)) MB used / $((allocated/1048576)) MB allocated"

offline_count=$(count_offline_tokens)
echo "Offline tokens in stash: $offline_count"
echo ""

# Set baseline
echo "Setting baseline..."
read -r base_in base_out <<< "$(get_local_bytes)"
echo "Baseline: ${base_in}B in, ${base_out}B out"
echo ""

# Track
used_bytes=$used
bucket_bytes=$allocated
echo "Tracking (Ctrl+C to stop)..."
echo "TIME         USED       REMAIN      RATE_IN    RATE_OUT"
echo "----         -----      ------      -------    --------"

prev_in=$base_in
prev_out=$base_out
prev_time=$(date +%s)

while true; do
    read -r cur_in cur_out <<< "$(get_local_bytes)"
    cur_time=$(date +%s)
    
    delta_in=$((cur_in - prev_in))
    delta_out=$((cur_out - prev_out))
    elapsed=$((cur_time - prev_time))
    [ "$elapsed" -eq 0 ] && elapsed=1
    
    used_bytes=$((used_bytes + delta_in + delta_out))
    used_mb=$(echo "scale=2; $used_bytes/1048576" | bc)
    remain_bytes=$((bucket_bytes - used_bytes))
    remain_mb=$(echo "scale=2; $remain_bytes/1048576" | bc)
    
    rate_in=$(echo "scale=1; $delta_in/$elapsed/1024" | bc)
    rate_out=$(echo "scale=1; $delta_out/$elapsed/1024" | bc)
    
    # Maintain offline stash at 7 tokens
    offline_count=$(count_offline_tokens)
    if [ "$offline_count" -lt 7 ]; then
        echo "Stash low ($offline_count), adding token..."
        refill_stash
    fi
    
    # Check usage less often when we have plenty of data (> 10 MB)
    if [ "$remain_bytes" -gt $((10 * 1048576)) ]; then
        check_interval=5
    else
        check_interval=$INTERVAL
    fi
    
    # Auto topup when low
    if [ "$remain_bytes" -lt $((TOPUP_THRESHOLD_MB * 1048576)) ]; then
        echo ""
        echo ">>> TOPUP: ${remain_mb}MB left"
        if do_pay; then
            # After payment, assume we have a fresh 1 sat allocation
            used_bytes=0
            bucket_bytes=$bytes_per_sat
            echo ">>> Bucket refilled: 0 MB used / $((bytes_per_sat/1048576)) MB allocated"
        fi
        echo ""
    fi
    
    printf "$(date +%H:%M:%S)   %7s MB   %7s MB   %6s KB/s  %6s KB/s\n" \
        "$used_mb" "$remain_mb" "$rate_in" "$rate_out"
    
    prev_in=$cur_in
    prev_out=$cur_out
    prev_time=$cur_time
    
    sleep $check_interval
done
