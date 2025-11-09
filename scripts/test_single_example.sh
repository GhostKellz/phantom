#!/bin/bash
# Test a single example for memory leaks
# Usage: ./test_single_example.sh <demo-name>

DEMO_NAME=$1
TIMEOUT=${2:-3}

if [ -z "$DEMO_NAME" ]; then
    echo "Usage: $0 <demo-name> [timeout-seconds]"
    exit 1
fi

echo "Testing $DEMO_NAME for $TIMEOUT seconds..."

# Rebuild in debug mode
zig build -Doptimize=Debug > /dev/null 2>&1

# Run the demo and capture output
output=$(timeout $TIMEOUT zig build "$DEMO_NAME" 2>&1 || true)

# Check for leaks
if echo "$output" | grep -q "memory leak detected"; then
    echo "❌ MEMORY LEAK DETECTED"
    echo "$output" | grep -A 10 "memory leak"
    exit 1
elif echo "$output" | grep -qi "error\|panic\|segfault"; then
    echo "❌ ERROR/CRASH"
    echo "$output" | grep -i "error\|panic" | head -5
    exit 2
else
    echo "✅ PASSED (no leaks detected in $TIMEOUT second run)"
    exit 0
fi
