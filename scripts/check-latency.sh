#!/bin/bash
# Checks keystroke→results (HammerBench, p99 < 16 ms), each ↓ through the clipboard (p95 < 16 ms)
# and hotkey→visible panel (p95 < 50 ms).
set -euo pipefail
cd "$(dirname "$0")/.."
swift run -c release HammerBench
swift run -c release HammerBench clipnav

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
report() {   # $1 label, stdin: ms values
    sort -n | awk -v label="$1" '
        { v[NR] = $1 }
        END { p95 = v[int((NR - 1) * 0.95) + 1]; printf "%s: %d opens  p95 %.2f ms  max %.2f ms\n", label, NR, p95, v[NR];
              if (p95 >= 50) { print "FAIL: p95 ≥ 50 ms"; exit 1 } else print "PASS" }'
}
grep show_ms "$OUT" | tail -n +2 | cut -d= -f2 | report "launcher warm"

# Clipboard with 10 large screenshots in history (exercises list thumbnails).
PNG="$WORK/shot.png"
sips -z 1600 2560 "/System/Library/Desktop Pictures/.thumbnails/Calibrate 5120x3200.jpg" -s format png --out "$PNG" >/dev/null
for i in $(seq 1 10); do
    sips -s formatOptions $((40 + i)) "$PNG" >/dev/null 2>&1 || true   # vary bytes so entries don't dedupe
    printf '%s' "$i" >> "$PNG"
    osascript -l JavaScript -e "ObjC.import('AppKit'); var pb = \$.NSPasteboard.pasteboardWithName('dev.hammer.debug'); pb.clearContents; pb.setDataForType(\$.NSData.dataWithContentsOfFile('$PNG'), 'public.png');" >/dev/null
    sleep 0.4
done
BEFORE=$(grep -c show_ms "$OUT")
for n in $(seq 1 $RUNS); do
    kill -USR2 $PID
    for _ in $(seq 1 200); do [ "$(grep -c show_ms "$OUT")" -ge $((BEFORE + n)) ] && break; sleep 0.02; done
    kill -HUP $PID
    sleep 0.2
done
grep show_ms "$OUT" | tail -n $RUNS | cut -d= -f2 | report "clipboard with 10 screenshots"
