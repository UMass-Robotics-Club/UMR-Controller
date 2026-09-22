#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
cd "$script_dir"

# Accept DEVICE_ID override (CoreDevice ID from `xcrun devicectl list devices`).
device_id="${DEVICE_ID:-}"
if [[ -z "$device_id" ]]; then
  device_id="$(xcrun devicectl list devices | awk 'match($0,/[A-F0-9]{8}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{12}/){print substr($0,RSTART,RLENGTH); exit}')"
fi

if [[ -z "$device_id" ]]; then
  echo "No connected iPhone detected by devicectl."
  echo "Plug in your iPhone, unlock it, and trust this computer."
  exit 1
fi

echo "Using device: $device_id"

echo "Building signed iPhone app..."
xcodebuild -project UMRRemote.xcodeproj \
  -scheme UMRRemote \
  -destination 'generic/platform=iOS' \
  -configuration Debug \
  build >/tmp/umrremote-device-build.log

app_path="$(find ~/Library/Developer/Xcode/DerivedData/UMRRemote-*/Build/Products/Debug-iphoneos -maxdepth 1 -name 'UMRRemote.app' | head -n 1)"
if [[ -z "$app_path" ]]; then
  echo "Could not locate built .app bundle."
  echo "See log: /tmp/umrremote-device-build.log"
  exit 1
fi

echo "Installing app on iPhone..."
xcrun devicectl device install app --device "$device_id" "$app_path"

echo "Launching app..."
if ! xcrun devicectl device process launch --device "$device_id" com.umr.remote; then
  echo
  echo "Install succeeded, but launch was denied by iOS security policy."
  echo "Open UMRRemote manually on your iPhone once to complete trust checks."
fi

echo "Done."
