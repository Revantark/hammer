#!/bin/bash
# Builds build/Hammer.app (release, stripped, signed with a stable identity).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product Hammer
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
