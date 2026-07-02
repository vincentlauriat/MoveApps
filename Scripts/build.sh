#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "✗ XcodeGen non installé. brew install xcodegen" >&2; exit 1
fi

echo "→ Génération du projet Xcode…"
xcodegen generate

echo "→ Build Debug…"
xcodebuild -project MoveApps.xcodeproj \
  -scheme MoveApps \
  -configuration Debug \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20

APP="$ROOT/build/Build/Products/Debug/MoveApps.app"
echo "✅ Build OK : $APP"
if [ "${1:-}" = "run" ]; then open "$APP"; fi
