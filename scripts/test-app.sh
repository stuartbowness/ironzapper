#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
mkdir -p build Artifacts
xcrun swiftc -swift-version 5 -O -target arm64-apple-macos26.0 -parse-as-library Sources/IronZapperCore/*.swift Shared/*.swift App/AppModel.swift App/HelperClient.swift App/ContentView.swift Tests/AppIntegration/main.swift -o build/app-integration
build/app-integration
