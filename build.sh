#!/usr/bin/env bash
#
# build-dmg.sh — build, sign and package a macOS app into a signed .dmg
#
# Usage:   ./build-dmg.sh
# Needs:   Xcode command line tools, create-dmg (brew install create-dmg)
#
# Edit the CONFIG section below, or override any value from the environment:
#   SCHEME=MyApp SIGN_IDENTITY="Developer ID Application: Me (ABCDE12345)" ./build-dmg.sh

set -euo pipefail

# ----------------------------- CONFIG ---------------------------------------
APP_NAME="EVE Operator"                  # name of the .app (without extension)
SCHEME="EVE Operator"                  # Xcode scheme to build
PROJECT="eve-operator.xcodeproj"      # .xcodeproj (or set WORKSPACE instead)
WORKSPACE="${WORKSPACE:-}"                     # .xcworkspace, leave empty if unused
CONFIGURATION="${CONFIGURATION:-Release}"

# Leave empty to auto-detect the first "Developer ID Application" identity
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
ENTITLEMENTS="${ENTITLEMENTS:-}"               # optional path to .entitlements file

# Optional notarization: create a profile once with
#   xcrun notarytool store-credentials "notary-profile" --apple-id ... --team-id ... --password ...
NOTARY_PROFILE="notary-profile"

BUILD_DIR="${BUILD_DIR:-build}"
DIST_DIR="${DIST_DIR:-dist}"
VERSION="${VERSION:-}"                         # leave empty to read from Info.plist
# ----------------------------------------------------------------------------

log()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
fail() { printf '\n\033[1;31mError: %s\033[0m\n' "$*" >&2; exit 1; }

# --- Dependency checks ------------------------------------------------------
command -v xcodebuild >/dev/null || fail "xcodebuild not found (install Xcode / command line tools)"
command -v create-dmg >/dev/null || fail "create-dmg not found (brew install create-dmg)"
command -v codesign   >/dev/null || fail "codesign not found"

# --- Signing identity -------------------------------------------------------
if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="$(security find-identity -v -p codesigning \
    | grep "Developer ID Application" | head -n1 \
    | sed -E 's/.*"(.+)".*/\1/' || true)"
  [[ -n "$SIGN_IDENTITY" ]] || fail "No 'Developer ID Application' identity found. Set SIGN_IDENTITY."
fi
log "Using identity: $SIGN_IDENTITY"

# --- Clean ------------------------------------------------------------------
log "Cleaning"
rm -rf "$BUILD_DIR" "$DIST_DIR"
mkdir -p "$BUILD_DIR" "$DIST_DIR"

# --- Build ------------------------------------------------------------------
log "Building $SCHEME ($CONFIGURATION)"
if [[ -n "$WORKSPACE" ]]; then
  TARGET_ARGS=(-workspace "$WORKSPACE")
else
  TARGET_ARGS=(-project "$PROJECT")
fi

xcodebuild "${TARGET_ARGS[@]}" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  CONFIGURATION_BUILD_DIR="$PWD/$BUILD_DIR/products" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_IDENTITY="" \
  clean build | { command -v xcpretty >/dev/null && xcpretty || cat; }

APP_PATH="$BUILD_DIR/products/$APP_NAME.app"
[[ -d "$APP_PATH" ]] || fail "Build finished but $APP_PATH was not found (check APP_NAME)"

# --- Version ----------------------------------------------------------------
if [[ -z "$VERSION" ]]; then
  VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
    "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "1.0")"
fi
DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION.dmg"

# --- Sign the app -----------------------------------------------------------
log "Signing $APP_NAME.app"
SIGN_ARGS=(--force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY")
[[ -n "$ENTITLEMENTS" ]] && SIGN_ARGS+=(--entitlements "$ENTITLEMENTS")
codesign "${SIGN_ARGS[@]}" "$APP_PATH"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"

# --- Create the DMG ---------------------------------------------------------
log "Creating $DMG_PATH"
STAGING="$BUILD_DIR/dmg-staging"
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$APP_PATH" "$STAGING/"

create-dmg \
  --volname "$APP_NAME" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 100 \
  --icon "$APP_NAME.app" 150 190 \
  --hide-extension "$APP_NAME.app" \
  --app-drop-link 450 190 \
  "$DMG_PATH" \
  "$STAGING/"

# --- Sign the DMG -----------------------------------------------------------
log "Signing DMG"
codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG_PATH"
codesign --verify --verbose=2 "$DMG_PATH"

# --- Notarize (optional) ----------------------------------------------------
if [[ -n "$NOTARY_PROFILE" ]]; then
  log "Notarizing (this can take a few minutes)"
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG_PATH"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG_PATH" || true
else
  log "Skipping notarization (NOTARY_PROFILE not set)"
fi

log "Done: $DMG_PATH"
