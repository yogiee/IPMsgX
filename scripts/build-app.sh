#!/bin/bash
# Build IPMsgX as a proper macOS .app bundle
# Usage: ./scripts/build-app.sh [release|debug]

set -euo pipefail

CONFIG="${1:-release}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
APP_NAME="IPMsgX"
BUNDLE_ID="com.ipmsgx.app"
VERSION="1.0"
BUILD_NUMBER="1"

echo "=== Building $APP_NAME ($CONFIG) ==="

# Step 1: Build with SPM
echo "  [1/6] Compiling with Swift Package Manager..."
if [ "$CONFIG" = "release" ]; then
    swift build -c release --package-path "$PROJECT_DIR" 2>&1
    BUILT_BINARY="$PROJECT_DIR/.build/release/$APP_NAME"
else
    swift build --package-path "$PROJECT_DIR" 2>&1
    BUILT_BINARY="$PROJECT_DIR/.build/arm64-apple-macosx/debug/$APP_NAME"
fi

if [ ! -f "$BUILT_BINARY" ]; then
    echo "ERROR: Built binary not found at $BUILT_BINARY"
    exit 1
fi

# Step 2: Create .app bundle structure
echo "  [2/6] Creating app bundle..."
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Step 3: Copy executable
echo "  [3/6] Copying executable..."
cp "$BUILT_BINARY" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# SPM resource bundle contents are already in Contents/Resources/ via actool and manual copies
# No need to copy the SPM resource bundle — Bundle.main handles it in .app context

# Step 4: Create Info.plist with resolved values
echo "  [4/6] Generating Info.plist..."
cat > "$APP_BUNDLE/Contents/Info.plist" << PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleDisplayName</key>
	<string>$APP_NAME</string>
	<key>CFBundleExecutable</key>
	<string>$APP_NAME</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleIconName</key>
	<string>AppIcon</string>
	<key>CFBundleIdentifier</key>
	<string>$BUNDLE_ID</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>$APP_NAME</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>$VERSION</string>
	<key>CFBundleVersion</key>
	<string>$BUILD_NUMBER</string>
	<key>LSMinimumSystemVersion</key>
	<string>15.0</string>
	<key>NSHumanReadableCopyright</key>
	<string>Copyright © 2026. All rights reserved.</string>
	<key>NSLocalNetworkUsageDescription</key>
	<string>IPMsgX uses the local network to discover and communicate with other IP Messenger clients.</string>
	<key>NSBonjourServices</key>
	<array>
		<string>_ipmsg._udp</string>
	</array>
	<key>LSUIElement</key>
	<false/>
</dict>
</plist>
PLISTEOF

# Step 5: Compile asset catalog and generate .icns
echo "  [5/6] Compiling assets and app icon..."
XCASSETS_DIR="$PROJECT_DIR/IPMsgX/Resources/Assets.xcassets"

# Compile asset catalog into .car (for menu bar icon, imagesets, etc.)
if [ -d "$XCASSETS_DIR" ]; then
    xcrun actool "$XCASSETS_DIR" \
        --compile "$APP_BUNDLE/Contents/Resources" \
        --platform macosx \
        --minimum-deployment-target 15.0 \
        --app-icon AppIcon \
        --output-partial-info-plist "$BUILD_DIR/assetcatalog_generated_info.plist" \
        2>&1 || echo "  Warning: actool returned non-zero"
fi

# Generate .icns from source PNGs using iconutil (actool produces incomplete icns)
APPICONSET="$XCASSETS_DIR/AppIcon.appiconset"
if [ -d "$APPICONSET" ]; then
    ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
    rm -rf "$ICONSET_DIR"
    mkdir -p "$ICONSET_DIR"
    # Map appiconset PNGs to iconset naming convention
    [ -f "$APPICONSET/icon_16x16.png" ]    && cp "$APPICONSET/icon_16x16.png"    "$ICONSET_DIR/icon_16x16.png"
    [ -f "$APPICONSET/icon_32x32.png" ]    && cp "$APPICONSET/icon_32x32.png"    "$ICONSET_DIR/icon_16x16@2x.png"
    [ -f "$APPICONSET/icon_32x32.png" ]    && cp "$APPICONSET/icon_32x32.png"    "$ICONSET_DIR/icon_32x32.png"
    [ -f "$APPICONSET/icon_64x64.png" ]    && cp "$APPICONSET/icon_64x64.png"    "$ICONSET_DIR/icon_32x32@2x.png"
    [ -f "$APPICONSET/icon_128x128.png" ]  && cp "$APPICONSET/icon_128x128.png"  "$ICONSET_DIR/icon_128x128.png"
    [ -f "$APPICONSET/icon_256x256.png" ]  && cp "$APPICONSET/icon_256x256.png"  "$ICONSET_DIR/icon_128x128@2x.png"
    [ -f "$APPICONSET/icon_256x256.png" ]  && cp "$APPICONSET/icon_256x256.png"  "$ICONSET_DIR/icon_256x256.png"
    [ -f "$APPICONSET/icon_512x512.png" ]  && cp "$APPICONSET/icon_512x512.png"  "$ICONSET_DIR/icon_256x256@2x.png"
    [ -f "$APPICONSET/icon_512x512.png" ]  && cp "$APPICONSET/icon_512x512.png"  "$ICONSET_DIR/icon_512x512.png"
    [ -f "$APPICONSET/icon_1024x1024.png" ] && cp "$APPICONSET/icon_1024x1024.png" "$ICONSET_DIR/icon_512x512@2x.png"
    # Convert to .icns
    iconutil --convert icns --output "$APP_BUNDLE/Contents/Resources/AppIcon.icns" "$ICONSET_DIR" 2>&1
    rm -rf "$ICONSET_DIR"
fi

# Copy standalone AppIcon.png for programmatic use
if [ -f "$PROJECT_DIR/IPMsgX/Resources/AppIcon.png" ]; then
    cp "$PROJECT_DIR/IPMsgX/Resources/AppIcon.png" "$APP_BUNDLE/Contents/Resources/"
fi

# Step 6: Ad-hoc code sign (no entitlements for now — sandboxing requires Developer ID)
echo "  [6/6] Code signing..."
codesign --force --sign - --deep "$APP_BUNDLE" 2>&1

echo ""
echo "=== Build complete ==="
echo "  App: $APP_BUNDLE"
echo "  Size: $(du -sh "$APP_BUNDLE" | cut -f1)"
echo ""
echo "To run: open $APP_BUNDLE"
echo "To copy to Applications: cp -R $APP_BUNDLE /Applications/"
