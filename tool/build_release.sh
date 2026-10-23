#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ ! -f android/key.properties ]]; then
  echo 'Release signing is required. Configure ignored android/key.properties as described in README.md.' >&2
  exit 1
fi
flutter pub get --enforce-lockfile
flutter analyze --fatal-infos
flutter test
flutter build apk --release --target-platform android-arm64
mkdir -p build/release
cp build/app/outputs/flutter-apk/app-release.apk build/release/ai-morning-briefing-arm64.apk
python3 - <<'PY'
from pathlib import Path
import hashlib, zipfile
p = Path('build/release/ai-morning-briefing-arm64.apk')
with zipfile.ZipFile(p) as apk:
    abis = {n.split('/')[1] for n in apk.namelist() if n.startswith('lib/') and n.endswith('.so')}
    assert abis == {'arm64-v8a'}, f'Unexpected native ABIs: {abis}'
Path('build/release/SHA256SUMS.txt').write_text(hashlib.sha256(p.read_bytes()).hexdigest() + '  ' + p.name + '\n')
print('arm64 APK and SHA256SUMS.txt written to build/release/')
PY
