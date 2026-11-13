#!/bin/bash
# Measures Hammer's memory (phys_footprint, same as Activity Monitor "Memory").
# Budget: fresh idle ≤ 10 MB, panel open ≤ 30 MB. Idle after use is allowed up to 30 MB (owner decision 2026-11-13:
# AppKit/ImageIO heap fragmentation isn't returnable; accepted instead of self-restarts). Uses a temp data dir and a private pasteboard;
# doesn't register global hotkeys or touch your clipboard.
set -euo pipefail
cd "$(dirname "$0")/.."
IDLE_MAX=10
OPEN_MAX=30
AFTER_MAX=30

scripts/build-app.sh >/dev/null
BIN="$PWD/build/Hammer.app/Contents/MacOS/Hammer"
WORK=$(mktemp -d)
OUT="$WORK/stdout.log"
HAMMER_DATA_DIR="$WORK/data" HAMMER_DEBUG_SIGNALS=1 "$BIN" >"$OUT" 2>"$WORK/stderr.log" &
PID=$!
trap 'kill $PID 2>/dev/null || true; rm -rf "$WORK"' EXIT

for _ in $(seq 1 100); do grep -q hammer_ready "$OUT" && break; sleep 0.1; done

mb() { footprint -f bytes --noCategories -p "$PID" 2>/dev/null | awk '/phys_footprint:/ {printf "%.1f", $2/1048576; exit}'; }
stable() {   # waits until two reads 1 s apart differ by < 0.5 MB
    local prev cur
    prev=$(mb)
    for _ in $(seq 1 15); do
        sleep 1
        cur=$(mb)
        if awk -v a="$prev" -v b="$cur" 'BEGIN { d = a - b; if (d < 0) d = -d; exit !(d < 0.5) }'; then echo "$cur"; return; fi
        prev=$cur
    done
    echo "$cur"
}

IDLE=$(stable)
kill -USR1 $PID; LAUNCHER=$(stable)
kill -HUP $PID; sleep 0.5

PNG="$WORK/shot.png"
sips -z 1600 2560 "/System/Library/Desktop Pictures/.thumbnails/Calibrate 5120x3200.jpg" -s format png --out "$PNG" >/dev/null
osascript -l JavaScript -e "ObjC.import('AppKit'); var pb = \$.NSPasteboard.pasteboardWithName('dev.hammer.debug'); pb.clearContents; pb.setDataForType(\$.NSData.dataWithContentsOfFile('$PNG'), 'public.png');" >/dev/null
sleep 1   # > one clipboard poll interval
kill -USR2 $PID; CLIPBOARD=$(stable)
kill -HUP $PID; AFTER=$(stable)

printf "%-28s %8s %8s\n" "state" "MB" "budget"
printf "%-28s %8s %8s\n" "idle" "$IDLE" "$IDLE_MAX"
printf "%-28s %8s %8s\n" "launcher open" "$LAUNCHER" "$OPEN_MAX"
printf "%-28s %8s %8s\n" "clipboard open (2560x1600)" "$CLIPBOARD" "$OPEN_MAX"
printf "%-28s %8s %8s\n" "idle after use" "$AFTER" "$AFTER_MAX"
PEAK=$(footprint -f bytes --noCategories -p "$PID" 2>/dev/null | awk '/phys_footprint_peak:/ {printf "%.1f", $2/1048576; exit}')
echo "peak: $PEAK MB"

awk -v i="$IDLE" -v l="$LAUNCHER" -v c="$CLIPBOARD" -v a="$AFTER" -v im="$IDLE_MAX" -v om="$OPEN_MAX" -v am="$AFTER_MAX" \
    'BEGIN { exit !(i <= im && a <= am && l <= om && c <= om) }' && echo "PASS" || { echo "FAIL: over budget"; exit 1; }
