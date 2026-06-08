#!/bin/bash
# Build, Developer-ID sign, notarize, staple, and zip Runway.app for
# distribution via Homebrew. Produces build/Runway-<version>.zip plus the
# sha256 and a ready-to-paste cask `url`/`sha256`/`version`.
#
# Auth:
#   * Local: store the App Store Connect API key once as a notarytool keychain
#     profile (then this script needs no env):
#
#       xcrun notarytool store-credentials runway-notary \
#         --key   <path-to-AuthKey_XXXX.p8> \
#         --key-id <key-id> \
#         --issuer <issuer-id>   # all three from App Store Connect
#
#   * CI: export NOTARY_KEY_PATH, NOTARY_KEY_ID, NOTARY_ISSUER_ID (see
#     .github/workflows/release.yml). The Developer ID cert is imported into a
#     temporary keychain there.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Auto-detect the Developer ID Application identity from the keychain so no team
# ID is hardcoded. Override by exporting SIGN_IDENTITY.
SIGN_IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning \
    | grep -o 'Developer ID Application: .*' | head -1 | sed 's/"$//')}"
if [ -z "$SIGN_IDENTITY" ]; then
    echo "No Developer ID Application identity found; set SIGN_IDENTITY." >&2
    exit 1
fi
APP="$ROOT/build/Runway.app"

# notarytool auth: locally use a stored keychain profile (NOTARY_PROFILE);
# in CI pass the App Store Connect API key directly (NOTARY_KEY_PATH/ID/ISSUER).
if [ -n "${NOTARY_KEY_PATH:-}" ]; then
    NOTARY_AUTH=(--key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID")
else
    NOTARY_AUTH=(--keychain-profile "${NOTARY_PROFILE:-runway-notary}")
fi

# Version from the bundle's CFBundleShortVersionString (set in build-app.sh).
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
    "$ROOT/build/Runway.app/Contents/Info.plist" 2>/dev/null || true)"

echo "==> Building + Developer ID signing (hardened runtime)"
SIGN_IDENTITY="$SIGN_IDENTITY" "$ROOT/Scripts/build-app.sh" release

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
    "$APP/Contents/Info.plist")"
ZIP="$ROOT/build/Runway-$VERSION.zip"

echo "==> Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "==> Zipping for notarization submission"
SUBMIT_ZIP="$ROOT/build/Runway-submit.zip"
/usr/bin/ditto -c -k --keepParent "$APP" "$SUBMIT_ZIP"

echo "==> Submitting to Apple notary service (this can take a few minutes)"
xcrun notarytool submit "$SUBMIT_ZIP" "${NOTARY_AUTH[@]}" --wait

echo "==> Stapling the ticket to the .app"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP" || true

echo "==> Zipping the stapled app for distribution"
rm -f "$ZIP" "$SUBMIT_ZIP"
/usr/bin/ditto -c -k --keepParent "$APP" "$ZIP"

SHA="$(shasum -a 256 "$ZIP" | awk '{print $1}')"

cat <<EOF

==> Done.
  Artifact : $ZIP
  Version  : $VERSION
  sha256   : $SHA

Cask fields (update Casks/tokens-runway.rb in saadjs/homebrew-tap):
  version "$VERSION"
  sha256  "$SHA"
  url     "https://github.com/saadjs/Runway/releases/download/v$VERSION/Runway-$VERSION.zip"

Next:
  gh release create v$VERSION "$ZIP" --repo saadjs/Runway --title "v$VERSION" --generate-notes
EOF
