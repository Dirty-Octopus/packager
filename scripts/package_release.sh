#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

bash scripts/build.sh --no-open

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Supporting/Info.plist)
APP="dist/Packager.app"
BASE="dist/Packager-${VERSION}-macos"

echo "▸ Creating ZIP"
rm -f "${BASE}.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "${BASE}.zip"

echo "▸ Creating DMG"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/Packager.app"
ln -s /Applications "$STAGE/Applications"
rm -f "${BASE}.dmg"
hdiutil create -quiet -volname "Packager" -srcfolder "$STAGE" -ov -format UDZO "${BASE}.dmg"
rm -rf "$STAGE"

echo "▸ Checksums"
shasum -a 256 "${BASE}.zip" "${BASE}.dmg" > "dist/SHA256SUMS.txt"
cat dist/SHA256SUMS.txt
echo "✓ Release artifacts in dist/"
