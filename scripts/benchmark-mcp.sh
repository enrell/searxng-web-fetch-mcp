#!/bin/bash

MCP_BINARY="${MCP_BINARY:-${HOME}/.local/bin/searxng-web-fetch-mcp}"
SEARXNG_URL="${SEARXNG_URL:-http://localhost:8888}"
BYPARR_URL="${BYPARR_URL:-http://localhost:8191}"
NUM_REQUESTS="${NUM_REQUESTS:-50}"
CONCURRENT="${CONCURRENT:-10}"

if [ ! -f "$MCP_BINARY" ]; then
    echo "ERROR: MCP binary not found at $MCP_BINARY"
    exit 1
fi

echo "=== MCP Server Benchmark ==="
echo "Binary: $MCP_BINARY"
echo "SearXNG: $SEARXNG_URL"
echo "Byparr: $BYPARR_URL"
echo "Requests: $NUM_REQUESTS"
echo "Concurrent: $CONCURRENT"
echo ""

send_request() {
    local id=$1
    local query=$2
    echo "{\"jsonrpc\":\"2.0\",\"id\":$id,\"method\":\"tools/call\",\"params\":{\"name\":\"searxng_web_search\",\"arguments\":{\"query\":\"$query\",\"num_results\":5}}}" | SEARXNG_URL="$SEARXNG_URL" BYPARR_URL="$BYPARR_URL" "$MCP_BINARY" 2>/dev/null
}

echo "Warmup (3 requests)..."
for i in 1 2 3; do
    send_request 0 "test" > /dev/null
done
echo "Warmup done."
echo ""

TOTAL_TIME=0
SUCCESS=0
FAIL=0
MIN_LATENCY=999999
MAX_LATENCY=0
LATENCIES=""

start_time=$(date +%s%N)

for i in $(seq 1 $NUM_REQUESTS); do
    (
        req_start=$(date +%s%N)
        RESPONSE=$(send_request $i "benchmark query $i")
        req_end=$(date +%s%N)
        
        latency=$(( (req_end - req_start) / 1000000 ))
        
        if echo "$RESPONSE" | grep -q '\\"success\\":true'; then
            echo "OK:$latency" > /tmp/bench_$i.txt
        else
            echo "FAIL:$latency" > /tmp/bench_$i.txt
        fi
    ) &
    
    if [ $((i % CONCURRENT)) -eq 0 ]; then
        wait
    fi
done

wait

end_time=$(date +%s%N)
wall_time=$(( (end_time - start_time) / 1000000 ))

for i in $(seq 1 $NUM_REQUESTS); do
    if [ -f /tmp/bench_$i.txt ]; then
        result=$(cat /tmp/bench_$i.txt)
        rm -f /tmp/bench_$i.txt
        
        status="${result%%:*}"
        latency="${result##*:}"
        
        if [ "$status" = "OK" ]; then
            SUCCESS=$((SUCCESS + 1))
            LATENCIES="$LATENCIES $latency"
            
            if [ $latency -lt $MIN_LATENCY ]; then
                MIN_LATENCY=$latency
            fi
            if [ $latency -gt $MAX_LATENCY ]; then
                MAX_LATENCY=$latency
            fi
        else
            FAIL=$((FAIL + 1))
        fi
    fi
done

TOTAL=$((SUCCESS + FAIL))
RPS=$(( NUM_REQUESTS * 1000 / wall_time ))

avg_latency=0
if [ $SUCCESS -gt 0 ]; then
    sum=0
    for lat in $LATENCIES; do
        sum=$((sum + lat))
    done
    avg_latency=$((sum / SUCCESS))
fi

echo "=== Results ==="
echo "Total requests:  $TOTAL"
echo "Successful:      $SUCCESS"
echo "Failed:          $FAIL"
echo "Success rate:    $(( SUCCESS * 100 / TOTAL ))%"
echo ""
echo "=== Performance ==="
echo "Total time:      ${wall_time}ms"
echo "Requests/sec:    $RPS"
echo ""
echo "=== Latency ==="
echo "Min:            ${MIN_LATENCY}ms"
echo "Max:            ${MAX_LATENCY}ms"
echo "Avg:            ${avg_latency}ms"
echo ""

if [ $RPS -gt 50 ]; then
    echo "Rating: Excellent (>$RPS req/s)"
elif [ $RPS -gt 20 ]; then
    echo "Rating: Good ($RPS req/s)"
elif [ $RPS -gt 10 ]; then
    echo "Rating: Moderate ($RPS req/s)"
else
    echo "Rating: Slow ($RPS req/s)"
fi
