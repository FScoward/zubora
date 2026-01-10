#!/bin/bash

# Configuration
APP_NAME="Zubora"
BUILD_DIR=".build/release"
APP_BUNDLE="$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "📦 Packaging $APP_NAME..."

# 1. Clean previous build
echo "cleaning previous bundle..."
rm -rf "$APP_BUNDLE"

# 2. Re-run build to be sure
# echo "Building release..."
# swift build -c release

# 3. Create Directory Structure
echo "Creating bundle structure..."
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# 4. Copy Binary
echo "Copying binary..."
cp "$BUILD_DIR/$APP_NAME" "$MACOS_DIR/"

# 5. Copy Info.plist
echo "Copying Info.plist..."
if [ -f "Info.plist" ]; then
    cp "Info.plist" "$CONTENTS_DIR/"
else
    echo "WARNING: Info.plist not found! Creating basic one..."
    cat <<EOF > "$CONTENTS_DIR/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.example.$APP_NAME</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
EOF
fi

# 6. Set Executable Permissions
chmod +x "$MACOS_DIR/$APP_NAME"

echo "✅ App Bundle created at: $APP_BUNDLE"
echo "To run: open $APP_BUNDLE"

# 7. Create ZIP for distribution
echo "🗜 Compressing..."
zip -r "$APP_NAME.zip" "$APP_BUNDLE"
echo "✅ Distribution package created: $APP_NAME.zip"
