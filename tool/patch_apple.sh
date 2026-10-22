#!/usr/bin/env bash
# Adds the Info.plist keys gshare needs on iOS and macOS. Safe to run more than once.
set -euo pipefail
cd "$(dirname "$0")/.."
PB=/usr/libexec/PlistBuddy

set_string() { "$PB" -c "Delete :$2" "$1" >/dev/null 2>&1 || true; "$PB" -c "Add :$2 string \"$3\"" "$1"; }
set_bool()   { "$PB" -c "Delete :$2" "$1" >/dev/null 2>&1 || true; "$PB" -c "Add :$2 bool $3" "$1"; }
set_bonjour() {
  "$PB" -c "Delete :NSBonjourServices" "$1" >/dev/null 2>&1 || true
  "$PB" -c "Add :NSBonjourServices array" "$1"
  "$PB" -c "Add :NSBonjourServices:0 string _gshare._tcp" "$1"
}

LOCAL_NET="gshare uses the local network to find nearby devices and send files directly to them."
CAMERA="gshare uses the camera to scan connection QR codes."

IOS=ios/Runner/Info.plist
if [[ -f "$IOS" ]]; then
  set_string "$IOS" NSLocalNetworkUsageDescription "$LOCAL_NET"
  set_bonjour "$IOS"
  set_string "$IOS" NSCameraUsageDescription "$CAMERA"
  set_string "$IOS" NSPhotoLibraryUsageDescription "gshare lets you pick photos and videos to send."
  set_string "$IOS" NSPhotoLibraryAddUsageDescription "gshare saves received photos and videos to your library."
  # Show received files in the Files app.
  set_bool "$IOS" UIFileSharingEnabled true
  set_bool "$IOS" LSSupportsOpeningDocumentsInPlace true
  echo "Patched $IOS"
fi

MAC=macos/Runner/Info.plist
if [[ -f "$MAC" ]]; then
  set_string "$MAC" NSLocalNetworkUsageDescription "$LOCAL_NET"
  set_bonjour "$MAC"
  set_string "$MAC" NSCameraUsageDescription "$CAMERA"
  echo "Patched $MAC"
fi
