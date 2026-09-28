#!/bin/bash
# Creates only a disposable app and launch daemon for manual end-to-end testing.
# Run from Terminal: sudo scripts/create-system-fixture.sh
set -euo pipefail
if [ "$(id -u)" -ne 0 ] || [ -z "${SUDO_UID:-}" ]; then
  echo 'Run this script with sudo from your own Terminal session.' >&2
  exit 1
fi
TOKEN="$(uuidgen | tr '[:upper:]' '[:lower:]')"
LABEL="test.ironzapper.fixture.$TOKEN"
APP="/Applications/IronZapper Test Fixture $TOKEN.app"
PLIST="/Library/LaunchDaemons/$LABEL.plist"
mkdir -p "$APP/Contents/MacOS"
cp /bin/sleep "$APP/Contents/MacOS/fixture"
/usr/bin/plutil -create xml "$APP/Contents/Info.plist"
/usr/bin/plutil -insert CFBundleIdentifier -string "$LABEL" "$APP/Contents/Info.plist"
/usr/bin/plutil -insert CFBundleName -string 'IronZapper Test Fixture' "$APP/Contents/Info.plist"
/usr/bin/plutil -insert CFBundleExecutable -string fixture "$APP/Contents/Info.plist"
/usr/bin/plutil -insert CFBundlePackageType -string APPL "$APP/Contents/Info.plist"
/usr/bin/codesign --force --sign - "$APP"
/usr/bin/plutil -create xml "$PLIST"
/usr/bin/plutil -insert Label -string "$LABEL" "$PLIST"
/usr/bin/plutil -insert ProgramArguments -json "[]" "$PLIST"
/usr/bin/plutil -insert ProgramArguments.0 -string "$APP/Contents/MacOS/fixture" "$PLIST"
/usr/bin/plutil -insert ProgramArguments.1 -string 3600 "$PLIST"
/usr/bin/plutil -insert RunAtLoad -bool YES "$PLIST"
chmod 644 "$PLIST"
/bin/launchctl bootstrap system "$PLIST"
echo "Disposable application: $APP"
echo "Disposable service: $LABEL"
echo "Drop the application into IronZapper, select its launch daemon, and Move to Trash."
echo "Verify the daemon is absent from launchctl and its plist is in your Trash/IronZapper-* folder."
echo "If you stop testing, unload with: sudo launchctl bootout system/$LABEL"
echo "Then move this exact fixture app and plist to Trash."
