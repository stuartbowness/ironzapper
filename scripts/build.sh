#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
BUILD_DIR="$PWD/build"
APP="$BUILD_DIR/Iron Zapper.app"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
SIGN_IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk '/Apple Development:|Developer ID Application:/ {print $2; exit}')}"
if [ -z "$SIGN_IDENTITY" ]; then
  echo 'A valid Apple Development or Developer ID Application signing identity is required.' >&2
  exit 1
fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Library/LaunchDaemons"
COMMON=(-sdk "$SDK" -target arm64-apple-macos26.0 -swift-version 5 -O -framework Foundation -framework Security)
xcrun swiftc "${COMMON[@]}" -module-name IronZapperHelper Sources/IronZapperCore/*.swift Shared/*.swift Helper/*.swift -o "$APP/Contents/MacOS/IronZapperHelper"
xcrun swiftc "${COMMON[@]}" -framework AppKit -framework SwiftUI -framework ServiceManagement -parse-as-library -module-name IronZapper Sources/IronZapperCore/*.swift Shared/*.swift App/*.swift -o "$APP/Contents/MacOS/IronZapper"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/ai.toyo.IronZapper.Helper.plist "$APP/Contents/Library/LaunchDaemons/"
cp Resources/IconArtwork.png "$APP/Contents/Resources/IconArtwork.png"
cp Resources/Zap.wav "$APP/Contents/Resources/Zap.wav"
xcrun actool Resources/IronAppIcon.icon --compile "$APP/Contents/Resources" --platform macosx --minimum-deployment-target 26.0 --app-icon IronAppIcon --output-partial-info-plist "$BUILD_DIR/icon-info.plist" --output-format human-readable-text
codesign --force --options runtime --timestamp=none --identifier ai.toyo.IronZapper.Helper --sign "$SIGN_IDENTITY" "$APP/Contents/MacOS/IronZapperHelper"
codesign --force --options runtime --timestamp=none --sign "$SIGN_IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"
echo "Built and verified: $APP"
