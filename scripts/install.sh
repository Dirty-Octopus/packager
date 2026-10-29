#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ "${1:-}" == "--no-build" ]] || bash "$ROOT/scripts/build.sh"
APP="$ROOT/dist/Packager.app"
DEST="/Applications/Packager.app"
codesign --verify --deep --strict "$APP"
if [[ -w /Applications ]]; then
  if [[ -e "$DEST" ]]; then
    BACKUP_DIR="$ROOT/.build/installed-backups"
    mkdir -p "$BACKUP_DIR"
    mv "$DEST" "$BACKUP_DIR/Packager-$(date +%Y%m%d-%H%M%S)-$$.app"
  fi
  ditto "$APP" "$DEST"
else
  osascript - "$APP" "$ROOT/.build/installed-backups" <<'APPLESCRIPT'
on run argv
  set backupRoot to quoted form of (item 2 of argv)
  set backupPath to quoted form of ((item 2 of argv) & "/Packager-" & (do shell script "date +%Y%m%d-%H%M%S") & ".app")
  do shell script "mkdir -p " & backupRoot & " && if [ -e /Applications/Packager.app ]; then mv /Applications/Packager.app " & backupPath & "; fi && ditto " & quoted form of (item 1 of argv) & " /Applications/Packager.app" with administrator privileges
end run
APPLESCRIPT
fi
codesign --verify --deep --strict "$DEST"
open "$DEST"
echo "Installed $DEST"
