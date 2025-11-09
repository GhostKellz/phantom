#!/bin/bash
# Memory leak testing script for Phantom v0.8.1
# Tests all examples and reports memory leaks

set -e

echo "==========================================================="
echo "🔍 Phantom v0.8.1 - Memory Leak Detection"
echo "==========================================================="
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Build in debug mode
echo "Building in debug mode..."
zig build -Doptimize=Debug > /dev/null 2>&1

# List of demos to test
demos=(
    "demo-ai-chat"
    "demo-data-dashboard"
    "demo-data-visualization"
    "demo-feature-showcase"
    "demo-ghostty"
    "demo-grim"
    "demo-pkg"
    "demo-reaper"
    "demo-crypto"
    "demo-package-browser"
    "demo-theme-gallery"
    "demo-vxfw"
    "demo-zion"
    "demo-stability-test"
    "run-grove-demo"
    "demo-terminal-session"
)

# Results
declare -a passed
declare -a failed
declare -a errors

total=0
leaked=0
error_count=0

echo "Testing ${#demos[@]} examples..."
echo ""

for demo in "${demos[@]}"; do
    total=$((total + 1))
    echo -n "[$total/${#demos[@]}] Testing $demo... "

    # Run demo for 2 seconds and capture output
    output=$(timeout 2 zig build "$demo" 2>&1 || true)

    # Check for memory leaks in output
    # Zig's GPA will print leak info to stderr
    if echo "$output" | grep -q "memory leak"; then
        echo -e "${RED}LEAKED${NC}"
        failed+=("$demo")
        leaked=$((leaked + 1))

        # Extract leak info
        leak_info=$(echo "$output" | grep -A 5 "memory leak" | head -10)
        echo "  └─ $leak_info"
    elif echo "$output" | grep -qi "error\|panic\|segfault"; then
        echo -e "${RED}ERROR${NC}"
        errors+=("$demo")
        error_count=$((error_count + 1))
    else
        echo -e "${GREEN}PASSED${NC}"
        passed+=("$demo")
    fi
done

echo ""
echo "==========================================================="
echo "📊 Results Summary"
echo "==========================================================="
echo "Total tested:     $total"
echo -e "${GREEN}Passed (no leaks): ${#passed[@]}${NC}"
echo -e "${YELLOW}Errors:            ${#errors[@]}${NC}"
echo -e "${RED}Memory leaks:      ${#failed[@]}${NC}"
echo ""

if [ ${#failed[@]} -gt 0 ]; then
    echo -e "${RED}❌ Examples with memory leaks:${NC}"
    for demo in "${failed[@]}"; do
        echo "  - $demo"
    done
    echo ""
fi

if [ ${#errors[@]} -gt 0 ]; then
    echo -e "${YELLOW}⚠️  Examples with errors:${NC}"
    for demo in "${errors[@]}"; do
        echo "  - $demo"
    done
    echo ""
fi

if [ ${#passed[@]} -eq $total ]; then
    echo -e "${GREEN}✅ All examples passed! Zero memory leaks.${NC}"
    exit 0
else
    echo -e "${RED}❌ Found issues. See above for details.${NC}"
    exit 1
fi
