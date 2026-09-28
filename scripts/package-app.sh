#!/usr/bin/env bash
set -e

# ==============================================================================
# Script Pembuatan Standalone Bundle macOS (.app) untuk TossShare
# ==============================================================================

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

APP_NAME="TossShare"
BUNDLE_DIR="$PROJECT_DIR/$APP_NAME.app"
CONTENTS_DIR="$BUNDLE_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "🚀 [1/4] Mengompilasi Universal Binary Release (arm64 & x86_64)..."
swift build -c release --arch arm64 --arch x86_64

echo "📦 [2/4] Menyiapkan struktur bundle $APP_NAME.app..."
rm -rf "$BUNDLE_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Salin binary yang telah dikompilasi
RELEASE_BIN="$PROJECT_DIR/.build/out/Products/Release/TossShareApp"
if [ ! -f "$RELEASE_BIN" ]; then
    # Fallback jika SPM menggunakan direktori build default
    RELEASE_BIN=$(find "$PROJECT_DIR/.build" -name "TossShareApp" -type f -perm +111 | grep "Release" | head -n 1)
fi

cp "$RELEASE_BIN" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

echo "🎨 [3/4] Memasang AppIcon.icns..."
if [ -f "$PROJECT_DIR/Assets/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/Assets/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
elif [ -f "$PROJECT_DIR/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

echo "📝 [4/4] Membangkitkan Contents/Info.plist..."
cat << 'EOF' > "$CONTENTS_DIR/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>TossShare</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.tossshare.mac</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>TossShare</string>
    <key>CFBundleDisplayName</key>
    <string>TossShare</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSUIElement</key>
    <false/>
    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>TossShare menggunakan Bluetooth Low Energy untuk mendeteksi perangkat Samsung Quick Share terdekat.</string>
    <key>NSLocalNetworkUsageDescription</key>
    <string>TossShare menggunakan jaringan lokal nirkabel Wi-Fi untuk transfer berkas berkecepatan tinggi.</string>
</dict>
</plist>
EOF

echo "✅ Sukses! Aplikasi siap dijalankan: $BUNDLE_DIR"
echo "👉 Untuk memasang ke sistem: cp -R \"$BUNDLE_DIR\" /Applications/"
