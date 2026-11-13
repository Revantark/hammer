#!/bin/bash
# Runs the full test suite N times (default 5) to catch flaky tests.
set -uo pipefail
cd "$(dirname "$0")/.."
RUNS="${1:-5}"
PASSED=0
LOG=$(mktemp)
for i in $(seq 1 "$RUNS"); do
    if swift test >"$LOG" 2>&1; then
        PASSED=$((PASSED + 1))
        echo "run $i: $(grep -E 'Test run with' "$LOG" | tail -1)"
    else
        echo "run $i: FAILED"; grep -E "✘|error:" "$LOG" | head -20
    fi
done
rm -f "$LOG"
echo "$PASSED/$RUNS passed"
[ "$PASSED" -eq "$RUNS" ]
