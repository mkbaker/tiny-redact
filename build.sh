#!/bin/bash
# Builds TinyRedact.app into ./build. Needs Xcode or the Command Line Tools (xcode-select --install).
#
#   ./build.sh                 # ad-hoc signed
#   SIGN_ID="Apple Development: you@example.com (TEAMID)" ./build.sh
#
# With ad-hoc signing macOS may ask for Screen Recording permission again after each rebuild.
# Signing with a real identity (any free Apple Development cert) makes the permission stick.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="build/TinyRedact.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/TinyRedact "$APP/Contents/MacOS/TinyRedact"

# CFBundleIdentifier must match Prefs.appDomain in Settings.swift, or the --redact CLI reads different settings.
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>TinyRedact</string>
    <key>CFBundleDisplayName</key><string>TinyRedact</string>
    <key>CFBundleIdentifier</key><string>com.local.tinyredact</string>
    <key>CFBundleExecutable</key><string>TinyRedact</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign "${SIGN_ID:--}" "$APP"
echo "Built $APP"
echo "Run it with:  open $APP"
echo "Or install:   cp -R $APP /Applications/"
