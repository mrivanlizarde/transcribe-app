#!/bin/zsh
# Builds Hark.app — a real, launchable macOS app bundle.
# SwiftPM produces the executable; this assembles the bundle around it.
set -e

SRC="${0:A:h}"
CONFIG="${1:-debug}"
APP="$SRC/dist/Hark.app"

echo "Building ($CONFIG)..."
cd "$SRC"
swift build -c "$CONFIG" --product Hark
swift build -c "$CONFIG" --product make-icon

BIN="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN/Hark" "$APP/Contents/MacOS/Hark"

echo "Drawing icon..."
ICONSET="$SRC/dist/Hark.iconset"
rm -rf "$ICONSET"
"$BIN/make-icon" "$ICONSET" >/dev/null
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Hark</string>
  <key>CFBundleDisplayName</key><string>Hark</string>
  <key>CFBundleIdentifier</key><string>com.ivanlizarde.hark</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>Hark</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <!-- LSUIElement is NOT set: the Dock icon is toggled at runtime via
       NSApp.setActivationPolicy so the setting can change without a relaunch. -->
  <key>NSSupportsAutomaticTermination</key><false/>
  <key>NSSupportsSuddenTermination</key><false/>
</dict>
</plist>
PLIST

# Ad-hoc sign so the app can hold TCC permissions and launch cleanly.
codesign --force --deep --sign - "$APP" 2>/dev/null || true

echo "Built: $APP"
