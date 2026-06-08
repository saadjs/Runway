#!/bin/bash
# Build Runway.app: a menu-bar-only (LSUIElement) bundle, ad-hoc signed so
# macOS keychain "Always Allow" grants persist across launches.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${1:-release}"
APP="$ROOT/build/Runway.app"

cd "$ROOT"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Runway"

BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Runway"
[ -f "$ROOT/Assets/AppIcon.icns" ] && cp "$ROOT/Assets/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
# Ship the SwiftPM resource bundle in Resources (Bundle.main.resourceURL),
# where Bundle.module resolves it and codesign accepts the nested bundle.
RES_BUNDLE="$BIN_DIR/Runway_Runway.bundle"
DEST_BUNDLE="$APP/Contents/Resources/Runway_Runway.bundle"
if [ -d "$RES_BUNDLE" ]; then
    cp -R "$RES_BUNDLE" "$APP/Contents/Resources/"
    # SwiftPM emits a flat resource folder; give it an Info.plist so it is a
    # valid, signable macOS bundle (Bundle.module still resolves it).
    cat > "$DEST_BUNDLE/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>app.runway.resources</string>
    <key>CFBundleName</key><string>Runway_Runway</string>
    <key>CFBundlePackageType</key><string>BNDL</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
</dict>
</plist>
PLIST
fi

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Runway</string>
    <key>CFBundleDisplayName</key><string>Runway</string>
    <key>CFBundleIdentifier</key><string>app.runway</string>
    <key>CFBundleExecutable</key><string>Runway</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHumanReadableCopyright</key><string>Runway</string>
</dict>
</plist>
PLIST

# Stable ad-hoc identity keeps keychain grants from re-prompting each launch.
# Sign the nested resource bundle first, then the app (inside-out).
if [ -d "$APP/Contents/Resources/Runway_Runway.bundle" ]; then
    codesign --force --sign - "$APP/Contents/Resources/Runway_Runway.bundle"
fi
codesign --force --sign - --identifier app.runway "$APP"

echo "Built: $APP"
