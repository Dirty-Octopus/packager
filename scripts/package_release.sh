#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
ARCH="${ARCH:-$(uname -m)}"
case "$ARCH" in arm64) ;; x86_64|x64) ARCH=x64;; *) echo "Unsupported ARCH: $ARCH" >&2; exit 1;; esac
case "${1:-}" in "") ARCH="$ARCH" bash scripts/build.sh;; --no-build) ;; *) echo "Usage: ARCH=arm64|x64 bash scripts/package_release.sh [--no-build]" >&2; exit 2;; esac
export PACKAGER_RELEASE_ARCH="$ARCH"
python3 - <<'PY'
import datetime
import hashlib
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile

root = Path.cwd()
arch = os.environ['PACKAGER_RELEASE_ARCH']
version = (root / 'Sources/Packager/Resources/Version.txt').read_text().strip()
app = root / 'dist/Packager.app'
metadata = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
assert metadata['CFBundleShortVersionString'] == version, 'App and source versions differ'
actual = subprocess.check_output(['/usr/bin/lipo', '-archs', str(app / 'Contents/MacOS/Packager')], text=True).strip()
assert actual == {'arm64': 'arm64', 'x64': 'x86_64'}[arch], f'Wrong app architecture: {actual}'
subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(app)], check=True)
assert subprocess.check_output([str(app / 'Contents/Resources/backend/Packager'), '--version'], text=True).strip() == f'Packager {version}'
base = root / 'dist' / f'Packager-{version}-macos-{arch}'
zip_path, dmg_path = Path(str(base) + '.zip'), Path(str(base) + '.dmg')
for artifact in (zip_path, dmg_path):
    if artifact.exists():
        backup = root / '.build/previous-releases' / (datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f') + '-' + artifact.name)
        backup.parent.mkdir(parents=True, exist_ok=True)
        artifact.rename(backup)
subprocess.run(['/usr/bin/ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(app), str(zip_path)], check=True)
with tempfile.TemporaryDirectory(prefix=f'packager-{version}-{arch}-', dir=root / '.build') as staging:
    staging = Path(staging)
    subprocess.run(['/usr/bin/ditto', str(app), str(staging / 'Packager.app')], check=True)
    (staging / 'Applications').symlink_to('/Applications')
    subprocess.run(['/usr/bin/hdiutil', 'create', '-quiet', '-volname', 'Packager', '-srcfolder', str(staging), '-format', 'UDZO', str(dmg_path)], check=True)
subprocess.run(['/usr/bin/hdiutil', 'verify', str(dmg_path)], check=True)
files = sorted((root / 'dist').glob(f'Packager-{version}-macos-*.zip')) + sorted((root / 'dist').glob(f'Packager-{version}-macos-*.dmg'))
lines = []
for file in files:
    with file.open('rb') as stream:
        hasher = hashlib.sha256()
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            hasher.update(chunk)
        digest = hasher.hexdigest()
    lines.append(f'{digest}  {file.name}')
(root / 'dist/SHA256SUMS.txt').write_text('\n'.join(lines) + '\n')
print('\n'.join(lines))
print(f'Release artifacts ready: {arch} / {version}')
PY
