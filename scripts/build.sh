#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
ARCH="${ARCH:-$(uname -m)}"
VERSION="$(tr -d '\n' < Sources/Packager/Resources/Version.txt)"
mkdir -p .build/backend dist
swift build -c release --arch arm64 --arch x86_64
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
cp "$BIN_DIR/Packager" .build/backend/Packager
ditto "$BIN_DIR/Packager_Packager.bundle" .build/backend/Packager_Packager.bundle
[[ "$(.build/backend/Packager --version)" == "Packager $VERSION" ]]
swift scripts/make_brand_icon.swift Resources/AppIcon.png
ICONSET="$ROOT/.build/AppIcon.iconset"
mkdir -p "$ICONSET"
for spec in "16 icon_16x16.png" "32 icon_16x16@2x.png" "32 icon_32x32.png" "64 icon_32x32@2x.png" "128 icon_128x128.png" "256 icon_128x128@2x.png" "256 icon_256x256.png" "512 icon_256x256@2x.png" "512 icon_512x512.png" "1024 icon_512x512@2x.png"; do
  sips -z "${spec%% *}" "${spec%% *}" Resources/AppIcon.png --out "$ICONSET/${spec#* }" >/dev/null
done
iconutil -c icns "$ICONSET" -o .build/AppIcon.icns
rm -rf "$ICONSET"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" Supporting/Info.plist
VERSION="$VERSION" node --input-type=module <<'JS'
import fs from 'node:fs';
const path = 'desktop/package.json';
const data = JSON.parse(fs.readFileSync(path));
data.version = process.env.VERSION;
data.build.mac.extendInfo.CFBundleShortVersionString = process.env.VERSION;
fs.writeFileSync(path, JSON.stringify(data, null, 2) + '\n');
JS
npm ci --prefix desktop --no-audit --no-fund
case "$ARCH" in arm64) export ELECTRON_INSTALL_ARCH=arm64;; x86_64|x64) export ELECTRON_INSTALL_ARCH=x64;; *) echo "Unsupported ARCH: $ARCH" >&2; exit 1;; esac
node scripts/prepare_electron.cjs
npm run build --prefix desktop
case "$ARCH" in arm64) ELECTRON_ARCH=arm64; OUTPUT=mac-arm64;; x86_64|x64) ELECTRON_ARCH=x64; OUTPUT=mac;; *) echo "Unsupported ARCH: $ARCH" >&2; exit 1;; esac
(cd desktop && npx electron-builder --mac dir --"$ELECTRON_ARCH")
APP="$ROOT/dist/Packager.app"
rm -rf "$APP"
ditto "$ROOT/desktop/release/$OUTPUT/Packager.app" "$APP"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
"$APP/Contents/Resources/backend/Packager" --version
echo "Built $APP ($ARCH)"
