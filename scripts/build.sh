#!/usr/bin/env bash
# Builds build/DynamicIsland.app from the current checkout.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="DynamicIsland"
CONFIG="${CONFIG:-release}"
BRANCH="${UPDATE_BRANCH:-main}"

echo "Building $APP_NAME ($CONFIG)…"
swift build -c "$CONFIG" --product "$APP_NAME"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

APP="$ROOT/build/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp "$ROOT/scripts/self-update.sh" "$APP/Contents/Resources/self-update.sh"

COMMIT="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
REPO_URL="$(git remote get-url origin 2>/dev/null || echo "")"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

sed \
    -e "s|__VERSION__|$VERSION|g" \
    -e "s|__BUILD__|$BUILD_NUMBER|g" \
    -e "s|__COMMIT__|$COMMIT|g" \
    -e "s|__REPO_URL__|$REPO_URL|g" \
    -e "s|__BRANCH__|$BRANCH|g" \
    "$ROOT/Support/Info.plist" > "$APP/Contents/Info.plist"

codesign --force --sign - "$APP" >/dev/null

echo "Built $APP (commit ${COMMIT:0:7})"
