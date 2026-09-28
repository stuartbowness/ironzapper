#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk '/Apple Development:|Developer ID Application:/ {print $2; exit}')}"
xcrun swiftc -swift-version 5 -target arm64-apple-macos26.0 -parse-as-library Sources/IronZapperCore/*.swift Shared/*.swift scripts/helper-probe.swift -o build/helper-probe
codesign --force --options runtime --timestamp=none --identifier ai.toyo.IronZapper --sign "$IDENTITY" build/helper-probe
build/helper-probe
codesign --force --options runtime --timestamp=none --identifier ai.toyo.IronZapper.WrongPeer --sign "$IDENTITY" build/helper-probe
if build/helper-probe; then
  echo 'FAIL: helper accepted the wrong peer identity'; exit 1
fi
echo 'PASS: real XPC accepted the correct peer and rejected an unrelated identity.'
