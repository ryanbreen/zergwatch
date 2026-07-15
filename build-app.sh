#!/usr/bin/env bash
# build-app.sh — build Zerg Watch, assemble the .app bundle, and (optionally)
# code sign it.
#
# Signing is OPTIONAL and controlled via environment variables:
#   ZERGWATCH_SIGN_IDENTITY    Common Name of a code signing identity in your
#                              keychain (e.g. a self-signed "Zerg Watch Local
#                              Signing" cert, or a Developer ID identity).
#   ZERGWATCH_KEYCHAIN         Path to the keychain containing that identity.
#   ZERGWATCH_KEYCHAIN_PASSWORD  Optional; if set, the keychain is unlocked
#                              with this password before signing.
#
# If ZERGWATCH_SIGN_IDENTITY / ZERGWATCH_KEYCHAIN are not set, the app is
# signed ad-hoc instead. Ad-hoc signing changes the app's cdhash on every
# rebuild, which means macOS TCC permission grants (Accessibility, Input
# Monitoring) do NOT survive rebuilds — you'll need to re-grant them each
# time. See README.md for a recipe to make your own stable local cert.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$DIR/ZergWatch.app"
BUNDLE_ID="com.wrb.apmmeter"

echo "==> swift build -c release"
( cd "$DIR" && swift build -c release )

echo "==> assemble .app bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$DIR/.build/release/ZergWatch" "$APP/Contents/MacOS/ZergWatch"
cp "$DIR/Sources/ZergWatch/Resources/Info.plist" "$APP/Contents/Info.plist"

if [[ -n "${ZERGWATCH_SIGN_IDENTITY:-}" && -n "${ZERGWATCH_KEYCHAIN:-}" ]]; then
    echo "==> sign with $ZERGWATCH_SIGN_IDENTITY"
    if [[ -n "${ZERGWATCH_KEYCHAIN_PASSWORD:-}" ]]; then
        security unlock-keychain -p "$ZERGWATCH_KEYCHAIN_PASSWORD" "$ZERGWATCH_KEYCHAIN"
    fi
    codesign --force --deep --sign "$ZERGWATCH_SIGN_IDENTITY" --identifier "$BUNDLE_ID" --keychain "$ZERGWATCH_KEYCHAIN" "$APP"
else
    echo "==> no ZERGWATCH_SIGN_IDENTITY/ZERGWATCH_KEYCHAIN set; signing ad-hoc"
    echo "    (ad-hoc signing means Accessibility/Input Monitoring grants won't survive rebuilds — see README.md)"
    codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
fi

codesign --verify --deep --strict "$APP"
codesign -dvvv "$APP" 2>&1 | grep -iE 'Authority=|Identifier='

echo "==> built + signed: $APP"
echo "    relaunch:  osascript -e 'tell application \"Zerg Watch\" to quit'; open \"$APP\""
