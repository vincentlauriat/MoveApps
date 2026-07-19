#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SPARKLE_VERSION="2.9.1"
TOOLS_DIR="$ROOT/.sparkle-tools"

# Pinned SHA-256 of Sparkle-$SPARKLE_VERSION.tar.xz. The Sparkle project publishes no checksum on
# its GitHub release page, so this is a trust-on-first-use pin: computed locally with
# `shasum -a 256` from the archive downloaded on 2026-07-19 from the official release URL below
# (asset contents verified to contain bin/sign_update and bin/generate_keys). Bump both this value
# and SPARKLE_VERSION together when upgrading Sparkle.
SPARKLE_SHA256="c0dde519fd2a43ddfc6a1eb76aec284d7d888fe281414f9177de3164d98ba4c7"

if [ -x "$TOOLS_DIR/bin/sign_update" ]; then
  echo "✓ Sparkle tools déjà présents ($SPARKLE_VERSION)"
  exit 0
fi

echo "→ Téléchargement Sparkle $SPARKLE_VERSION tools…"
mkdir -p "$TOOLS_DIR"

# Download to a temp file first, verify its checksum, and only extract on a match — never pipe an
# unverified archive straight into tar.
ARCHIVE="$(mktemp -t sparkle-tools.tar.xz)"
trap 'rm -f "$ARCHIVE"' EXIT
curl -fsSL -o "$ARCHIVE" \
  "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz"

ACTUAL_SHA256="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"
if [ "$ACTUAL_SHA256" != "$SPARKLE_SHA256" ]; then
  echo "✗ Checksum SHA-256 invalide pour Sparkle-$SPARKLE_VERSION.tar.xz" >&2
  echo "  attendu : $SPARKLE_SHA256" >&2
  echo "  obtenu  : $ACTUAL_SHA256" >&2
  echo "  Téléchargement rejeté, extraction annulée." >&2
  exit 1
fi

tar -xJf "$ARCHIVE" -C "$TOOLS_DIR"
echo "✅ Sparkle tools installés dans $TOOLS_DIR"
echo ""
echo "ONE-TIME SETUP (Phase 4, repo privé — pas d'auto-update réseau en v1) :"
echo "  $TOOLS_DIR/bin/generate_keys --account MoveApps"
echo "  → Copie la clé publique dans project.yml (SUPublicEDKey) le jour où un feed est mis en place"
