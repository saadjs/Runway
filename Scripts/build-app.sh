#!/bin/bash
# Build the menu-bar-only Runway.app; ad-hoc signed unless SIGN_IDENTITY is set.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${1:-release}"
APP="$ROOT/build/Runway.app"

SIGN_IDENTITY="${SIGN_IDENTITY:--}"
SIGN_FLAGS=(--force --sign "$SIGN_IDENTITY")
if [ "$SIGN_IDENTITY" != "-" ]; then
    SIGN_FLAGS+=(--options runtime --timestamp)
fi

APP_VERSION="${APP_VERSION:-1.10}"
APP_BUILD="${APP_BUILD:-1}"

cd "$ROOT"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Runway"

BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Runway"
[ -f "$ROOT/Assets/AppIcon.icns" ] && cp "$ROOT/Assets/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
# Must live in Contents/Resources: codesign rejects unsealed content at the app root.
RES_BUNDLE="$BIN_DIR/Runway_Runway.bundle"
DEST_BUNDLE="$APP/Contents/Resources/Runway_Runway.bundle"
if [ ! -d "$RES_BUNDLE" ]; then
    echo "ERROR: resource bundle not found at $RES_BUNDLE — provider logos would be missing." >&2
    exit 1
fi
cp -R "$RES_BUNDLE" "$APP/Contents/Resources/"
# Flat bundles (older SwiftPM) need a root Info.plist to sign; Contents/ layouts (6.4+) must not have one.
if [ -d "$DEST_BUNDLE/Contents" ]; then
    RES_PLIST="$DEST_BUNDLE/Contents/Info.plist"
else
    RES_PLIST="$DEST_BUNDLE/Info.plist"
fi
if [ ! -f "$RES_PLIST" ]; then
cat > "$RES_PLIST" <<'PLIST'
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

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" \
    -c "Set :CFBundleVersion $APP_BUILD" "$APP/Contents/Info.plist"

# Sign inside-out: the nested resource bundle first.
codesign "${SIGN_FLAGS[@]}" "$DEST_BUNDLE"
codesign "${SIGN_FLAGS[@]}" --identifier app.runway "$APP"

LOGO_DIR="$DEST_BUNDLE"
[ -d "$DEST_BUNDLE/Contents/Resources" ] && LOGO_DIR="$DEST_BUNDLE/Contents/Resources"
for logo in claude codex opencode; do
    if [ ! -f "$LOGO_DIR/$logo.pdf" ]; then
        echo "ERROR: $logo.pdf missing from $LOGO_DIR after packaging." >&2
        exit 1
    fi
done
codesign --verify --deep --strict "$APP"

echo "Built: $APP (signed: $SIGN_IDENTITY)"
