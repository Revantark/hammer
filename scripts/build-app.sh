#!/bin/bash
# Builds build/Hammer.app (release, tuned for this Mac's CPU, stripped, signed with a stable identity).
set -euo pipefail
cd "$(dirname "$0")/.."

# Tune for this Mac's CPU (e.g. "Apple M4" -> apple-m4). HAMMER_CPU overrides; HAMMER_CPU=generic builds portable.
CPU="${HAMMER_CPU:-$(sysctl -n machdep.cpu.brand_string 2>/dev/null | sed -nE 's/^Apple (M[0-9]+).*/apple-\1/p' | tr '[:upper:]' '[:lower:]')}"
CPU_FLAGS=()
if [ -n "$CPU" ] && [ "$CPU" != "generic" ]; then
    CPU_FLAGS=(-Xswiftc -target-cpu -Xswiftc "$CPU" -Xcc "-mcpu=$CPU")
    echo "Optimizing for $CPU"
fi
swift build -c release --product Hammer ${CPU_FLAGS[@]+"${CPU_FLAGS[@]}"}
APP=build/Hammer.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/Hammer "$APP/Contents/MacOS/Hammer"
cp Resources/Info.plist "$APP/Contents/Info.plist"
strip -x "$APP/Contents/MacOS/Hammer"

IDENTITY="${HAMMER_SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
    IDENTITY=$(security find-identity -p codesigning | grep -m1 "Apple Development" | sed -E 's/.*"(.*)"/\1/' || true)
fi
if [ -z "$IDENTITY" ]; then
    IDENTITY="Hammer Local Signing"
fi
codesign --force --sign "$IDENTITY" --identifier dev.hammer.Hammer "$APP"
codesign --verify "$APP"
echo "$PWD/$APP"
