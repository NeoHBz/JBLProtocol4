#!/usr/bin/env bash
# Usage: bundle.sh <debug|release> <out.app>. Builds the package and assembles an unsigned menu bar .app.
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:?debug|release}"; APP="${2:?output .app path}"
swift build -c "$CONFIG" 2>&1 | grep -E "error:|warning:|Compiling|Build complete" | tail -5
BIN="$(swift build -c "$CONFIG" --show-bin-path)/JBLProtocol4"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/JBLProtocol4"
cp Resources/Info.plist "$APP/Contents/Info.plist"
scripts/product-images.sh "$APP/Contents/Resources/ProductImages"
PB=/usr/libexec/PlistBuddy
"$PB" -c "Set :CFBundleIdentifier ${JBL_BUNDLE_ID:-local.jblprotocol4}" "$APP/Contents/Info.plist"
"$PB" -c "Set :CFBundleShortVersionString ${JBL_VERSION:-0.1.0}" "$APP/Contents/Info.plist"
"$PB" -c "Set :CFBundleVersion ${GITHUB_RUN_NUMBER:-1}" "$APP/Contents/Info.plist"
echo "Bundled $APP"
