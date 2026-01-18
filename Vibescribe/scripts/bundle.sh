#!/bin/bash
set -e

cd "$(dirname "$0")/.."

APP_NAME="Vibescribe"
BUNDLE_ID="com.vibescribe.app"
BUILD_DIR=".build/debug"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

echo "Building $APP_NAME..."
swift build

echo "Creating app bundle..."
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy executable
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/"

# Copy entitlements
cp "Vibescribe.entitlements" "$APP_BUNDLE/Contents/Resources/" 2>/dev/null || true

# Create Info.plist
cat > "$APP_BUNDLE/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Vibescribe needs microphone access to transcribe your voice.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>Vibescribe needs accessibility access for global hotkeys.</string>
</dict>
</plist>
EOF

# Sign with Apple Development certificate (preserves TCC permissions across rebuilds)
SIGNING_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep "Apple Development" | head -1 | sed 's/.*"\(.*\)"/\1/')

if [ -n "$SIGNING_IDENTITY" ]; then
    echo "Signing with: $SIGNING_IDENTITY"
    codesign --force --sign "$SIGNING_IDENTITY" --entitlements "Vibescribe.entitlements" "$APP_BUNDLE"
else
    echo "No Apple Development certificate found, using ad-hoc signing..."
    codesign --force --sign - --entitlements "Vibescribe.entitlements" "$APP_BUNDLE" 2>/dev/null || true
fi

echo "Done! Run with:"
echo "  open $APP_BUNDLE"
