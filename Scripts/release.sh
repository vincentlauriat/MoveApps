#!/usr/bin/env bash
# Build a Release MoveApps.app, Developer ID sign with Hardened Runtime,
# notarize via Apple, staple the ticket, and package it as a distributable .dmg.
#
# Usage: ./Scripts/release.sh <version>
#   e.g. ./Scripts/release.sh 0.1.0
#
# Prerequisites (one-time setup — already satisfied on this Mac, see MEMORY.md):
#   - "Developer ID Application: Vincent LAURIAT (KFLACS69T9)" certificate in
#     the login keychain.
#   - notarytool credentials stored under the keychain profile
#     "AppliMacVincentGithub" — a generic profile shared across Vincent's apps
#     (MarkdownViewer, RTKInfos, ...), not per-project. Same Apple ID/team, so
#     it works for MoveApps too with zero extra setup. Only needed again if
#     this credential is ever revoked:
#       xcrun notarytool store-credentials "AppliMacVincentGithub" \
#         --apple-id "vincent@lauriat.fr" --team-id "KFLACS69T9"
#
# Override defaults if needed:
#   SIGNING_IDENTITY="Developer ID Application: …"  ./Scripts/release.sh 0.1.0
#   NOTARY_PROFILE="AppliMacVincentGithub"          ./Scripts/release.sh 0.1.0
#
# Local dry run (build + sign + DMG, no notarization, no Sparkle signing):
#   SKIP_NOTARIZE=1 ./Scripts/release.sh 0.1.0
#
# Auto-update (since 2026-07-12, repo now public — see MEMORY.md): this script also
# Sparkle-signs the DMG and (re)writes appcast.xml at the repo root. IMPORTANT: bump
# CURRENT_PROJECT_VERSION in project.yml every release, not just MARKETING_VERSION —
# Sparkle compares sparkle:version against the running app's CFBundleVersion, and two
# releases sharing the same build number look identical to it (see MarkdownViewer's
# release-full.sh for the same warning).
#
# Outputs release/MoveApps-<version>.dmg, fully notarized and Sparkle-signed.

set -euo pipefail

VERSION="${1:?Usage: ./Scripts/release.sh <version>  (e.g. ./Scripts/release.sh 0.1.0)}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# 1. Sanity check: project.yml must declare the same MARKETING_VERSION
if ! grep -q "MARKETING_VERSION: \"$VERSION\"" project.yml; then
  echo "✗ MARKETING_VERSION in project.yml does not match $VERSION" >&2
  echo "  Found:" >&2
  grep "MARKETING_VERSION" project.yml | sed 's/^/    /' >&2
  echo "  Bump project.yml first, then re-run." >&2
  exit 1
fi

# 2. Regenerate xcodeproj
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "✗ XcodeGen not installed. brew install xcodegen" >&2
  exit 1
fi
echo "→ xcodegen generate"
xcodegen generate >/dev/null

# 3. Build Release
echo "→ xcodebuild Release"
xcodebuild -project MoveApps.xcodeproj \
  -scheme MoveApps \
  -configuration Release \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  build 2>&1 | tail -5

APP="$ROOT/build/Build/Products/Release/MoveApps.app"
if [ ! -d "$APP" ]; then
  echo "✗ Build did not produce $APP" >&2
  exit 1
fi

# 4. Stage to a clean directory, Developer ID sign with Hardened Runtime, package.
SIGNING_IDENTITY="${SIGNING_IDENTITY:-Developer ID Application: Vincent LAURIAT (KFLACS69T9)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-AppliMacVincentGithub}"

STAGING_DIR="$(mktemp -d)"
STAGING="$STAGING_DIR/MoveApps.app"
echo "→ Staging to $STAGING_DIR"
ditto --norsrc --noextattr --noacl "$APP" "$STAGING"

codesign_ts() {
  local target="$1"
  local attempt
  for attempt in 1 2 3 4 5; do
    if codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$target" 2>&1; then
      return 0
    fi
    if [ "$attempt" -lt 5 ]; then
      echo "  ↻ codesign failed (attempt $attempt/5), retrying in 5s…"
      sleep 5
    fi
  done
  echo "✗ codesign $target failed after 5 attempts" >&2
  return 1
}

echo "→ Codesigning Sparkle.framework nested binaries (deepest first)"
SPARKLE_FW="$STAGING/Contents/Frameworks/Sparkle.framework"
if [ -d "$SPARKLE_FW" ]; then
  SPARKLE_VER="$SPARKLE_FW/Versions/B"
  codesign_ts "$SPARKLE_VER/Autoupdate"
  codesign_ts "$SPARKLE_VER/XPCServices/Downloader.xpc"
  codesign_ts "$SPARKLE_VER/XPCServices/Installer.xpc"
  codesign_ts "$SPARKLE_VER/Updater.app"
  codesign_ts "$SPARKLE_FW"
fi

echo "→ Codesigning nested MoveAppsCore.framework / MoveAppsUI.framework"
for FW in "$STAGING/Contents/Frameworks/MoveAppsCore.framework" "$STAGING/Contents/Frameworks/MoveAppsUI.framework"; do
  if [ -d "$FW" ]; then codesign_ts "$FW"; fi
done

echo "→ Codesigning the app itself with Developer ID + Hardened Runtime"
codesign_ts "$STAGING"
codesign --verify --strict --deep "$STAGING"

RELEASE_DIR="$ROOT/release"
mkdir -p "$RELEASE_DIR"
DMG="$RELEASE_DIR/MoveApps-$VERSION.dmg"
rm -f "$DMG"

echo "→ Creating $DMG"
hdiutil create -volname "MoveApps $VERSION" -srcfolder "$STAGING" \
  -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$DMG" >/dev/null

rm -rf "$STAGING_DIR"

# 5. Notarize the DMG with Apple, then staple the ticket — unless SKIP_NOTARIZE=1.
if [ "${SKIP_NOTARIZE:-0}" = "1" ]; then
  DMG_SIZE=$(ls -lh "$DMG" | awk '{print $5}')
  echo ""
  echo "⚠️  SKIP_NOTARIZE=1 : DMG signé mais NON notarisé, non stapled: $DMG ($DMG_SIZE)"
  echo "   Gatekeeper bloquera son ouverture sur une autre machine tant qu'il n'est pas notarisé."
  echo "   Relance sans SKIP_NOTARIZE une fois le profil \"$NOTARY_PROFILE\" en place pour un DMG distribuable."
  exit 0
fi

echo "→ Submitting $DMG to Apple notary service (this takes 2–5 min)"
xcrun notarytool submit "$DMG" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait

echo "→ Stapling notarization ticket to the DMG"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

# 6. Sign the DMG with the Sparkle EdDSA key and (re)write appcast.xml so the
# in-app updater (Sparkle 2) can serve this version. Mirrors MarkdownViewer's
# release-full.sh, adapted for MoveApps' own keychain account and repo.
SPARKLE_TOOLS="$ROOT/.sparkle-tools"
if [ ! -x "$SPARKLE_TOOLS/bin/sign_update" ]; then
  echo "→ Fetching Sparkle tools (one-time setup)"
  "$ROOT/Scripts/fetch-sparkle-tools.sh"
fi

echo "→ Signing $DMG with Sparkle EdDSA key (account: MoveApps)"
SPARKLE_SIG_LINE=$("$SPARKLE_TOOLS/bin/sign_update" --account MoveApps "$DMG")

# Sparkle compares <sparkle:version> against the running app's CFBundleVersion, not
# the marketing version — read the actual build number baked into the .app.
BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP/Contents/Info.plist")

echo "→ Writing $ROOT/appcast.xml (sparkle:version=$BUILD_NUMBER, shortVersionString=$VERSION)"
PUB_DATE=$(date -R)
cat > "$ROOT/appcast.xml" <<APPCAST
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>MoveApps</title>
    <link>https://raw.githubusercontent.com/vincentlauriat/MoveApps/main/appcast.xml</link>
    <description>MoveApps release feed</description>
    <language>fr</language>
    <item>
      <title>v$VERSION</title>
      <pubDate>$PUB_DATE</pubDate>
      <sparkle:version>$BUILD_NUMBER</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>https://github.com/vincentlauriat/MoveApps/releases/tag/v$VERSION</sparkle:releaseNotesLink>
      <enclosure
        url="https://github.com/vincentlauriat/MoveApps/releases/download/v$VERSION/MoveApps-$VERSION.dmg"
        type="application/octet-stream"
        $SPARKLE_SIG_LINE />
    </item>
  </channel>
</rss>
APPCAST

DMG_SIZE=$(ls -lh "$DMG" | awk '{print $5}')
echo ""
echo "✅ Built, signed, notarized, stapled and Sparkle-signed: $DMG ($DMG_SIZE)"
echo "✅ appcast.xml written for v$VERSION"
echo ""
echo "Next steps to publish:"
echo "  1. gh release create v$VERSION $DMG --title \"v$VERSION\" --notes-file release/release-notes-$VERSION.md"
echo "  2. git add appcast.xml && git commit -m 'docs: appcast for v$VERSION' && git push"
echo ""
echo "After both, Sparkle clients on older versions will be offered the update on next check."
echo "First install on a new Mac is still manual (Sparkle updates an existing install, it doesn't bootstrap one)."
