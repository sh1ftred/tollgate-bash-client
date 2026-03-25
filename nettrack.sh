#!/bin/bash
# Network data usage tracker - tracks traffic from launch moment
# Usage: ./nettrack.sh [interval_seconds] [max_samples]

INTERVAL=${1:-2}
MAX_SAMPLES=${2:-30}

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

# Format bytes in pure bash
format_bytes() {
    local bytes=$1
    if [ "$bytes" -ge 1073741824 ]; then
        echo "$(echo "scale=1; $bytes/1073741824" | bc)G"
    elif [ "$bytes" -ge 1048576 ]; then
        echo "$(echo "scale=1; $bytes/1048576" | bc)M"
    elif [ "$bytes" -ge 1024 ]; then
        echo "$(echo "scale=1; $bytes/1024" | bc)K"
    else
        echo "${bytes}B"
    fi
}

# Temp files for state
STATE_IN=$(mktemp)
STATE_OUT=$(mktemp)

cleanup() {
    rm -f "$STATE_IN" "$STATE_OUT"
}
trap cleanup EXIT

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  Network Usage Tracker${NC}"
echo -e "${CYAN}  Tracking from: $(date)${NC}"
echo -e "${CYAN}  Interval: ${INTERVAL}s | Max samples: ${MAX_SAMPLES}${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

printf "${CYAN}%-20s %10s %10s %10s %10s${NC}\n" "PROCESS" "IN" "OUT" "Δ IN" "Δ OUT"
printf "${CYAN}%-20s %10s %10s %10s %10s${NC}\n" "-------" "---" "---" "----" "-----"

sample=0
while [ $sample -lt $MAX_SAMPLES ]; do
    ((sample++))
    timestamp=$(date +%H:%M:%S)
    
    # Capture and process nettop output
    nettop -P -L 1 -J bytes_in,bytes_out 2>/dev/null | tail -n +2 | while IFS=, read -r proc bin bout _; do
        proc_name=$(echo "$proc" | sed 's/\.[0-9]*$//')
        
        [ -z "$bin" ] && continue
        
        # Get previous values from state files
        prev_in=$(grep "^${proc}=" "$STATE_IN" 2>/dev/null | cut -d= -f2)
        prev_out=$(grep "^${proc}=" "$STATE_OUT" 2>/dev/null | cut -d= -f2)
        prev_in=${prev_in:-0}
        prev_out=${prev_out:-0}
        
        # Calculate delta
        delta_in=$((bin - prev_in))
        delta_out=$((bout - prev_out))
        
        # Show if meaningful activity (>1KB change or accumulated >10MB)
        if [ "$delta_in" -gt 1024 ] || [ "$delta_out" -gt 1024 ] || [ "$bin" -gt 10485760 ]; then
            printf "${GREEN}%-20s${NC} %10s %10s %10s %10s\n" \
                "${proc_name:0:20}" \
                "$(format_bytes $bin)" \
                "$(format_bytes $bout)" \
                "$(format_bytes $delta_in)" \
                "$(format_bytes $delta_out)"
        fi
        
        # Update state files
        grep -v "^${proc}=" "$STATE_IN" > "${STATE_IN}.tmp" 2>/dev/null
        mv "${STATE_IN}.tmp" "$STATE_IN"
        echo "${proc}=${bin}" >> "$STATE_IN"
        
        grep -v "^${proc}=" "$STATE_OUT" > "${STATE_OUT}.tmp" 2>/dev/null
        mv "${STATE_OUT}.tmp" "$STATE_OUT"
        echo "${proc}=${bout}" >> "$STATE_OUT"
    done
    
    echo "--- Sample $sample at $timestamp ---"
    sleep $INTERVAL
done

echo ""
echo -e "${CYAN}Tracking complete.${NC}"
