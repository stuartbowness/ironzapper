#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="${1:-build/Iron Zapper.app}"
TEAM_ID="$(codesign -dv --verbose=2 "$APP" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
[[ "$TEAM_ID" =~ ^[A-Z0-9]+$ ]] || { echo 'Invalid signing team'; exit 1; }
for entry in 'ai.toyo.IronZapper' 'ai.toyo.IronZapper.Helper'; do
  TARGET="$APP"
  if [ "$entry" = 'ai.toyo.IronZapper.Helper' ]; then TARGET="$APP/Contents/MacOS/IronZapperHelper"; fi
  REQUIREMENT="anchor apple generic and identifier \"$entry\" and certificate leaf[subject.OU] = \"$TEAM_ID\" and !(entitlement[\"com.apple.security.get-task-allow\"] exists)"
  codesign --verify --strict -R="$REQUIREMENT" "$TARGET"
  if codesign --verify -R="$REQUIREMENT" /usr/bin/true >/dev/null 2>&1; then
    echo 'Peer requirement incorrectly accepts an unrelated process'; exit 1
  fi
done
codesign --verify --deep --strict "$APP"
echo 'Both signed peers satisfy their requirements; unrelated executable rejected.'
