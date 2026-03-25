#!/bin/bash
# Total network usage tracker - plain text version
# Usage: ./nettotal.sh [interval_seconds] [max_samples]

INTERVAL=${1:-2}
MAX_SAMPLES=${2:-30}

# Get interface stats using netstat
get_totals() {
    netstat -ib | grep -E '^en[0-9]' | awk '{
        bytes_in += $7;
        bytes_out += $10;
    }
    END {
        print bytes_in, bytes_out
    }'
}

# Format bytes
format_bytes() {
    local bytes=$1
    if [ "$bytes" -ge 1073741824 ]; then
        echo "$(echo "scale=2; $bytes/1073741824" | bc) GB"
    elif [ "$bytes" -ge 1048576 ]; then
        echo "$(echo "scale=2; $bytes/1048576" | bc) MB"
    elif [ "$bytes" -ge 1024 ]; then
        echo "$(echo "scale=2; $bytes/1024" | bc) KB"
    else
        echo "${bytes} B"
    fi
}

echo "========================================"
echo "  Total Network Usage Tracker"
echo "  Tracking from: $(date)"
echo "  Interval: ${INTERVAL}s | Max samples: ${MAX_SAMPLES}"
echo "========================================"
echo ""

# Show active interface
echo "Active interface:"
netstat -i | grep -E '^en[0-9]|<--' | grep -v '^en[1-9]' | head -1
echo ""

# Header
printf "%-12s %12s %12s %10s %10s\n" "TIME" "TOTAL IN" "TOTAL OUT" "IN/s" "OUT/s"
printf "%-12s %12s %12s %10s %10s\n" "----" "--------" "---------" "----" "----"

prev_in=0
prev_out=0
sample=0
first=true

while [ $sample -lt $MAX_SAMPLES ]; do
    ((sample++))
    timestamp=$(date +%H:%M:%S)
    
    read -r cur_in cur_out <<< "$(get_totals)"
    
    if [ "$first" = true ]; then
        first=false
        prev_in=$cur_in
        prev_out=$cur_out
        printf "%-12s %12s %12s %10s %10s\n" \
            "$timestamp" \
            "$(format_bytes $cur_in)" \
            "$(format_bytes $cur_out)" \
            "---" \
            "---"
        [ $sample -lt $MAX_SAMPLES ] && sleep $INTERVAL
        continue
    fi
    
    delta_in=$((cur_in - prev_in))
    delta_out=$((cur_out - prev_out))
    
    rate_in=$(echo "scale=1; $delta_in/$INTERVAL" | bc)
    rate_out=$(echo "scale=1; $delta_out/$INTERVAL" | bc)
    
    printf "%-12s %12s %12s %10s %10s\n" \
        "$timestamp" \
        "$(format_bytes $cur_in)" \
        "$(format_bytes $cur_out)" \
        "${rate_in}B/s" \
        "${rate_out}B/s"
    
    prev_in=$cur_in
    prev_out=$cur_out
    
    [ $sample -lt $MAX_SAMPLES ] && sleep $INTERVAL
done

echo ""
echo "Tracking complete."
