#!/bin/bash
# Build Runway.app: a menu-bar-only (LSUIElement) bundle, ad-hoc signed so
# macOS keychain "Always Allow" grants persist across launches.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${1:-release}"
APP="$ROOT/build/Runway.app"

# Signing identity. Defaults to ad-hoc ("-") for local dev. For distribution,
# release.sh sets SIGN_IDENTITY to the Developer ID Application cert, which also
# enables the hardened runtime + secure timestamp required for notarization.
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
SIGN_FLAGS=(--force --sign "$SIGN_IDENTITY")
if [ "$SIGN_IDENTITY" != "-" ]; then
    SIGN_FLAGS+=(--options runtime --timestamp)
fi

# Marketing version (CFBundleShortVersionString). CI sets this from the git tag.
APP_VERSION="${APP_VERSION:-1.0}"
APP_BUILD="${APP_BUILD:-1}"

cd "$ROOT"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Runway"

BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Runway"
[ -f "$ROOT/Assets/AppIcon.icns" ] && cp "$ROOT/Assets/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
# Ship the SwiftPM resource bundle in Contents/Resources (Bundle.main.resourceURL):
# the standard, codesign-able location. It can NOT live at the app root where the
# generated `Bundle.module` accessor looks — codesign rejects unsealed content
# there — so `Logo.image` resolves it from Resources by hand (see Support.swift).
RES_BUNDLE="$BIN_DIR/Runway_Runway.bundle"
DEST_BUNDLE="$APP/Contents/Resources/Runway_Runway.bundle"
if [ ! -d "$RES_BUNDLE" ]; then
    echo "ERROR: resource bundle not found at $RES_BUNDLE — provider logos would be missing." >&2
    exit 1
fi
cp -R "$RES_BUNDLE" "$APP/Contents/Resources/"
# SwiftPM emits a flat resource folder; give it an Info.plist so it is a
# valid, signable macOS bundle.
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

# A stable identity keeps keychain grants from re-prompting each launch (ad-hoc
# for dev; Developer ID for releases, which also has a stable designated
# requirement). Sign the nested resource bundle first, then the app (inside-out).
if [ -d "$APP/Contents/Resources/Runway_Runway.bundle" ]; then
    codesign "${SIGN_FLAGS[@]}" "$APP/Contents/Resources/Runway_Runway.bundle"
fi
codesign "${SIGN_FLAGS[@]}" --identifier app.runway "$APP"

# Fail the build if the logos the popover renders aren't actually present and the
# signature isn't valid — this is exactly the breakage that shipped crashing builds.
for logo in claude codex; do
    if [ ! -f "$DEST_BUNDLE/$logo.pdf" ]; then
        echo "ERROR: $logo.pdf missing from $DEST_BUNDLE after packaging." >&2
        exit 1
    fi
done
codesign --verify --deep --strict "$APP"

echo "Built: $APP (signed: $SIGN_IDENTITY)"
