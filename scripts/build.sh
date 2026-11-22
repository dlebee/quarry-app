#!/bin/bash
# Build and install QuarryBuilders.  Usage: scripts/build.sh [iphone|fire|sim|all]
#   iphone: Godot iOS export -> xcodebuild (device) -> devicectl install on David's iPhone
#   fire:   Godot Android export -> adb install on the Fire tablet (wireless adb must be connected)
#   sim:    x86_64 simulator build (Godot's simulator library is x86_64 only; runs under Rosetta)
set -euo pipefail
cd "$(dirname "$0")/../godot"
what="${1:-all}"
# Your devices: copy scripts/devices.env.example to scripts/devices.env (git-ignored) and fill it in.
[[ -f ../scripts/devices.env ]] && source ../scripts/devices.env
IPHONE_UDID="${IPHONE_UDID:-}"           # xcodebuild destination id (xcrun xctrace list devices)
IPHONE_DEVICECTL="${IPHONE_DEVICECTL:-}" # devicectl id (xcrun devicectl list devices)
APPLE_TEAM="${APPLE_TEAM:-BJNLYJTA8W}"
TABLET_SERIAL="${TABLET_SERIAL:-}"       # Android serial as shown by `adb mdns services`
TABLET_IP="${TABLET_IP:-}"
mkdir -p build/ios
godot --headless --import >/dev/null 2>&1 || true

# Godot's export can exit non-zero even when it worked, which would stop the script under set -e:
# ignore the code and check that the output was actually written instead.
fresh() { [[ -e "$1" && $(( $(date +%s) - $(stat -f %m "$1") )) -lt 600 ]] || { echo "export failed: $1" >&2; exit 1; }; }
ios_export() { godot --headless --export-debug "iOS" build/ios/QuarryBuilders.ipa >/dev/null 2>&1 || true; fresh build/ios/QuarryBuilders.xcodeproj/project.pbxproj; }

if [[ "$what" == iphone || "$what" == all ]]; then
  ios_export
  (cd build/ios && xcodebuild -project QuarryBuilders.xcodeproj -scheme QuarryBuilders -configuration Debug -derivedDataPath dd-device \
     -destination "id=$IPHONE_UDID" -allowProvisioningUpdates DEVELOPMENT_TEAM="$APPLE_TEAM" CODE_SIGN_STYLE=Automatic build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)")
  xcrun devicectl device install app --device "$IPHONE_DEVICECTL" build/ios/dd-device/Build/Products/Debug-iphoneos/QuarryBuilders.app
fi
if [[ "$what" == fire || "$what" == all ]]; then
  export JAVA_HOME="${JAVA_HOME:-/Applications/Android Studio.app/Contents/jbr/Contents/Home}"
  godot --headless --export-debug "Android" build/QuarryBuilders.apk >/dev/null 2>&1 || true
  fresh build/QuarryBuilders.apk
  # Find the Fire tablet's current wireless-debugging address (the port changes); override with ADB_SERIAL=ip:port.
  serial="${ADB_SERIAL:-}"
  if [[ -z "$serial" ]]; then
    adb start-server >/dev/null 2>&1
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      # Take only the port from discovery: its IP can be wrong while an emulator is running.
      port=$(adb mdns services | grep "${TABLET_SERIAL:-adb-tls-connect}" | grep -oE ':[0-9]+' | tail -1 | tr -d : || true)
      [[ -n "$port" ]] && serial="${TABLET_IP:?set TABLET_IP in scripts/devices.env}:$port"
      [[ -n "$serial" ]] && break
      sleep 1
    done
  fi
  [[ -n "$serial" ]] || { echo "Fire tablet not found: turn on Wireless debugging" >&2; exit 1; }
  adb connect "$serial" >/dev/null
  adb -s "$serial" install -r build/QuarryBuilders.apk
fi
if [[ "$what" == sim ]]; then
  ios_export
  (cd build/ios && xcodebuild -project QuarryBuilders.xcodeproj -scheme QuarryBuilders -sdk iphonesimulator -configuration Debug -derivedDataPath dd \
     ARCHS=x86_64 ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)")
  xcrun simctl install booted build/ios/dd/Build/Products/Debug-iphonesimulator/QuarryBuilders.app
  xcrun simctl launch booted com.davidlebee.quarrybuilders
fi
