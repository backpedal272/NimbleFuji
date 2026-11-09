#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-only
#
# Builds a universal Release "Nimble Fuji.app" and packages it in a DMG with an
# Applications shortcut, "READ ME FIRST.txt" (the risk warning) and the license.
#
#   scripts/make-dmg.sh                                   # ad-hoc signed, for testing
#   TEAM_ID=ABCDE12345 NOTARY_PROFILE=notary scripts/make-dmg.sh   # for distribution
#
# With TEAM_ID, the app is archived and exported with Developer ID signing. Xcode
# must be signed in to that team (Settings › Accounts); it uses your Developer ID
# Application certificate, or Apple's cloud-managed one if the keychain has none.
# With NOTARY_PROFILE, the DMG is notarized and stapled. Create the profile once:
#
#   xcrun notarytool store-credentials notary
#
# Output: build/dmg/NimbleFuji-<version>.dmg
set -euo pipefail

cd "${0:A:h}/.."
ROOT=$PWD
BUILD="$ROOT/build/dmg"
DERIVED="$BUILD/DerivedData"
STAGE="$BUILD/stage"
APP_NAME="Nimble Fuji"
VOLUME_NAME="Nimble Fuji"
TEAM_ID="${TEAM_ID:-}"

if command -v xcodegen >/dev/null; then
    echo "==> Regenerating Xcode project"
    xcodegen generate --quiet
fi

rm -rf "$BUILD"
mkdir -p "$BUILD"

COMMON=(
    -project NimbleFuji.xcodeproj
    -scheme NimbleFuji
    -configuration Release
    -destination "generic/platform=macOS"
    -derivedDataPath "$DERIVED"
    ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO
)

if [[ -z "$TEAM_ID" ]]; then
    echo "==> No TEAM_ID set: ad-hoc signing (users will need “Open Anyway”)"
    xcodebuild build "${COMMON[@]}" \
        CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= \
        -quiet
    APP="$DERIVED/Build/Products/Release/$APP_NAME.app"
else
    echo "==> Archiving (arm64 + x86_64)"
    ARCHIVE="$BUILD/NimbleFuji.xcarchive"
    # The archive is ad-hoc signed; the export below re-signs it with Developer ID.
    xcodebuild archive "${COMMON[@]}" \
        -archivePath "$ARCHIVE" \
        CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM="$TEAM_ID" \
        -quiet

    echo "==> Exporting with Developer ID (team $TEAM_ID)"
    cat > "$BUILD/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>developer-id</string>
    <key>teamID</key><string>$TEAM_ID</string>
    <key>signingStyle</key><string>automatic</string>
    <key>destination</key><string>export</string>
</dict>
</plist>
EOF
    xcodebuild -exportArchive \
        -archivePath "$ARCHIVE" \
        -exportOptionsPlist "$BUILD/ExportOptions.plist" \
        -exportPath "$BUILD/export" \
        -allowProvisioningUpdates \
        -quiet
    APP="$BUILD/export/$APP_NAME.app"
fi

[[ -d "$APP" ]] || { echo "error: $APP was not built" >&2; exit 1; }
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="$BUILD/NimbleFuji-$VERSION.dmg"

echo "==> Verifying app signature"
codesign --verify --strict --deep "$APP"
codesign -dvv "$APP" 2>&1 | grep -E "^(Authority|Signature|TeamIdentifier|Runtime)" || true

if [[ -n "$TEAM_ID" && -n "${NOTARY_PROFILE:-}" ]]; then
    # Staple the app itself too, so it passes Gatekeeper offline once it's been
    # copied out of the DMG.
    echo "==> Notarizing the app (this can take a few minutes)"
    ditto -c -k --keepParent "$APP" "$BUILD/app.zip"
    xcrun notarytool submit "$BUILD/app.zip" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP"
    rm "$BUILD/app.zip"
fi

echo "==> Staging DMG contents"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"
cp "scripts/dmg/READ ME FIRST.txt" "$STAGE/READ ME FIRST.txt"
cp LICENSE "$STAGE/LICENSE.txt"

echo "==> Creating $DMG"
hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGE" \
    -fs HFS+ \
    -format UDZO -imagekey zlib-level=9 \
    -ov "$DMG" -quiet

if [[ -n "$TEAM_ID" ]]; then
    # Signing the DMG itself needs a Developer ID certificate in the keychain.
    # Without one, the notarized and stapled DMG still opens without warnings.
    DMG_IDENTITY=$(security find-identity -v -p codesigning \
        | grep "Developer ID Application" | grep "($TEAM_ID)" | head -1 \
        | sed -E 's/^ *[0-9]+\) ([0-9A-F]+) .*/\1/' || true)
    if [[ -n "$DMG_IDENTITY" ]]; then
        echo "==> Signing DMG"
        codesign --sign "$DMG_IDENTITY" --timestamp "$DMG"
    fi

    if [[ -n "${NOTARY_PROFILE:-}" ]]; then
        echo "==> Notarizing the DMG"
        xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
        xcrun stapler staple "$DMG"
        xcrun stapler validate "$DMG"
    else
        echo "==> NOTARY_PROFILE not set: skipping notarization"
    fi
fi

echo "==> Done: $DMG"
