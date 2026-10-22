#!/usr/bin/env bash
# Generates the platform folders around the hand-written code, fetches packages and,
# on macOS, adds the iOS/macOS privacy keys. flutter create never overwrites existing files.
set -euo pipefail
cd "$(dirname "$0")/.."

flutter create --org com.gshare --project-name gshare --platforms android,ios,windows,macos,linux .
flutter pub get

if [[ "$(uname)" == "Darwin" ]]; then
  bash tool/patch_apple.sh
fi

flutter analyze || true
echo
echo "Done. Run on a device: flutter run"
