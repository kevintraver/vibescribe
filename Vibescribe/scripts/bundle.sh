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
# Only create bundle structure if it doesn't exist (preserve TCC permissions)
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy executable (this is the only thing that changes on rebuild)
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/"

# Create Info.plist (only if needed or changed)
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

# Ad-hoc sign to maintain consistent identity for TCC
codesign --force --sign - "$APP_BUNDLE" 2>/dev/null || true

echo "Done! Run with:"
echo "  open $APP_BUNDLE"
