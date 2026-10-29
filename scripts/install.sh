#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/dist/Packager.app"
DEST="/Applications/Packager.app"

bash "$ROOT/scripts/build.sh"

echo "▸ Installing to $DEST"
if [[ -w /Applications ]]; then
    rm -rf "$DEST"
    ditto "$APP" "$DEST"
else
    echo "  /Applications needs administrator access — macOS will ask for your password."
    osascript - "$APP" <<'APPLESCRIPT'
on run argv
    set src to quoted form of (item 1 of argv)
    do shell script "rm -rf /Applications/Packager.app && ditto " & src & " /Applications/Packager.app" with administrator privileges
end run
APPLESCRIPT
fi

open "$DEST"
echo "✓ Installed $DEST"
