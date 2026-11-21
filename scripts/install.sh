#!/usr/bin/env bash
# Builds the app, installs it to /Applications (or ~/Applications) and launches it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/scripts/build.sh"

DEST="${INSTALL_DIR:-/Applications}"
if [ ! -w "$DEST" ]; then
    DEST="$HOME/Applications"
fi
mkdir -p "$DEST"

TARGET="$DEST/DynamicIsland.app"

pkill -x DynamicIsland 2>/dev/null || true
while pgrep -x DynamicIsland >/dev/null; do sleep 0.2; done

rm -rf "$TARGET"
ditto "$ROOT/build/DynamicIsland.app" "$TARGET"
open "$TARGET"

echo "Installed to $TARGET"
