#!/bin/bash
# Wraps the compiled `swift build -c release` binary into a minimal, proper
# GoProFusionStitcher.app you can double-click or drag to /Applications.
#
# Usage (from the GoProFusionStitcher project root):
#   swift build -c release
#   ./Scripts/make_app_bundle.sh

set -euo pipefail

APP_NAME="GoPro Fusion Stitcher"
BUNDLE_ID="org.local.goprofusionstitcher"
BIN_PATH=".build/release/GoProFusionStitcher"
APP_DIR="./${APP_NAME}.app"

if [ ! -f "$BIN_PATH" ]; then
    echo "error: $BIN_PATH not found. Run 'swift build -c release' first." >&2
    exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/GoProFusionStitcher"
chmod +x "$APP_DIR/Contents/MacOS/GoProFusionStitcher"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>GoProFusionStitcher</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Built with ffmpeg (GPL). See README for third-party notices.</string>
</dict>
</plist>
PLIST

# Ad-hoc code sign so Gatekeeper lets it run without a paid Developer ID.
codesign --force --deep --sign - "$APP_DIR" 2>/dev/null || true

echo "Built: $APP_DIR"
echo "Drag it to /Applications, or double-click to run."
echo "First launch: right-click > Open (once) to satisfy Gatekeeper for an ad-hoc signed app."
