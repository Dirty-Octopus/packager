#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
fi

CONFIG="${CONFIG:-release}"
UNIVERSAL="${UNIVERSAL:-1}"

echo "▸ Building Packager ($CONFIG)"
if [[ "$UNIVERSAL" == "1" ]]; then
    if swift build -c "$CONFIG" --arch arm64 --arch x86_64; then
        BIN_DIR="$(swift build -c "$CONFIG" --arch arm64 --arch x86_64 --show-bin-path)"
    else
        echo "  universal build unavailable, falling back to $(uname -m)"
        swift build -c "$CONFIG"
        BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
    fi
else
    swift build -c "$CONFIG"
    BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
fi
BIN="$BIN_DIR/Packager"

APP="$ROOT/dist/Packager.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/Packager"
chmod +x "$APP/Contents/MacOS/Packager"
cp Supporting/Info.plist "$APP/Contents/Info.plist"

if [[ -f Resources/AppIcon.png ]]; then
    echo "▸ Building AppIcon.icns"
    ICONSET="$ROOT/.build/AppIcon.iconset"
    rm -rf "$ICONSET"
    mkdir -p "$ICONSET"
    for spec in "16 icon_16x16.png" "32 icon_16x16@2x.png" "32 icon_32x32.png" \
                "64 icon_32x32@2x.png" "128 icon_128x128.png" "256 icon_128x128@2x.png" \
                "256 icon_256x256.png" "512 icon_256x256@2x.png" "512 icon_512x512.png" \
                "1024 icon_512x512@2x.png"; do
        size="${spec%% *}"
        name="${spec#* }"
        sips -z "$size" "$size" Resources/AppIcon.png --out "$ICONSET/$name" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
    rm -rf "$ICONSET"
else
    echo "  (no Resources/AppIcon.png — using the system default icon)"
fi

echo "▸ Signing (ad-hoc)"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo "✓ Built $APP"
if [[ "${1:-}" != "--no-open" && "${OPEN_APP:-0}" == "1" ]]; then
    open "$APP"
fi
