#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${ANDROID_HOME:?Set ANDROID_HOME to your Android SDK directory}"
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
python3 tool/verify_apk.py build/release/ai-morning-briefing-arm64.apk
"$ANDROID_HOME/build-tools/36.0.0/apksigner" verify --verbose build/release/ai-morning-briefing-arm64.apk
python3 - <<'PY'
from pathlib import Path
import hashlib
p = Path('build/release/ai-morning-briefing-arm64.apk')
Path('build/release/SHA256SUMS.txt').write_text(hashlib.sha256(p.read_bytes()).hexdigest() + '  ' + p.name + '\n')
print('arm64 APK and SHA256SUMS.txt written to build/release/')
PY
