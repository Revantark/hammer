#!/bin/bash
# Checks keystroke→results (HammerBench, p99 < 16 ms) and hotkey→visible panel (p95 < 50 ms).
set -euo pipefail
cd "$(dirname "$0")/.."
swift run -c release HammerBench

scripts/build-app.sh >/dev/null
BIN="$PWD/build/Hammer.app/Contents/MacOS/Hammer"
WORK=$(mktemp -d)
OUT="$WORK/stdout.log"
HAMMER_DATA_DIR="$WORK/data" HAMMER_DEBUG_SIGNALS=1 HAMMER_LOG_TIMING=1 "$BIN" >"$OUT" 2>/dev/null &
PID=$!
trap 'kill $PID 2>/dev/null || true; rm -rf "$WORK"' EXIT
for _ in $(seq 1 100); do grep -q hammer_ready "$OUT" && break; sleep 0.1; done

RUNS=21
for n in $(seq 1 $RUNS); do
    kill -USR1 $PID
    for _ in $(seq 1 100); do [ "$(grep -c show_ms "$OUT")" -ge "$n" ] && break; sleep 0.02; done
    kill -HUP $PID
    sleep 0.2
done
grep show_ms "$OUT" | head -1 | sed 's/^/cold (first open, builds panel): /'
grep show_ms "$OUT" | tail -n +2 | cut -d= -f2 | sort -n | awk '
    { v[NR] = $1 }
    END { p95 = v[int((NR - 1) * 0.95) + 1]; printf "warm opens: %d  p95 %.2f ms  max %.2f ms\n", NR, p95, v[NR];
          if (p95 >= 50) { print "FAIL: p95 ≥ 50 ms"; exit 1 } else print "PASS" }'
