#!/usr/bin/env bash
#
# Build a Developer-ID-signed and Apple-notarized PortyMcFolio.dmg.
#
# Output: dist/PortyMcFolio-{version}-{date}.dmg — passes Gatekeeper on any Mac.
#
# Prerequisites (verified at startup):
#   - A "Developer ID Application" certificate + private key in the login keychain.
#   - A notarytool keychain credential profile (default name: portymcfolio-notary).
#     Create with:
#       xcrun notarytool store-credentials portymcfolio-notary \
#         --key ~/.private_keys/AuthKey_XXXXXXXX.p8 \
#         --key-id XXXXXXXX \
#         --issuer <issuer-uuid>
#
# Overridable via env vars (no secrets — just labels):
#   SIGNING_IDENTITY  — codesign identity match (default: "Developer ID Application")
#   NOTARY_PROFILE    — notarytool keychain profile name (default: portymcfolio-notary)
#
# This script never reads or echoes the .p8 key. Credentials live only in the
# login keychain via `notarytool store-credentials`. The Team ID is auto-
# discovered from the installed Developer ID cert; nothing personal is
# hardcoded here.

set -euo pipefail

SIGNING_IDENTITY="${SIGNING_IDENTITY:-Developer ID Application}"
NOTARY_PROFILE="${NOTARY_PROFILE:-portymcfolio-notary}"

# ---- locate project root ----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

if [[ ! -f project.yml ]]; then
    echo "error: must be run from the PortyMcFolio project root" >&2
    exit 1
fi

# ---- preflight ----
echo "==> Preflight"

MATCH_COUNT=$(security find-identity -v -p codesigning | grep -c "$SIGNING_IDENTITY" || true)
if [[ "$MATCH_COUNT" -eq 0 ]]; then
    echo "error: no codesigning identity matches '$SIGNING_IDENTITY'" >&2
    echo "       run: security find-identity -v -p codesigning" >&2
    exit 1
fi
if [[ "$MATCH_COUNT" -gt 1 ]]; then
    echo "error: multiple codesigning identities match '$SIGNING_IDENTITY' — be more specific" >&2
    security find-identity -v -p codesigning | grep "$SIGNING_IDENTITY" >&2
    exit 1
fi

if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    echo "error: notarytool profile '$NOTARY_PROFILE' is missing or invalid" >&2
    echo "       (re)create with: xcrun notarytool store-credentials $NOTARY_PROFILE ..." >&2
    exit 1
fi

# Auto-discover the Team ID from the Developer ID cert subject so we never
# hardcode it. Team ID is the 10-char alphanumeric in the OU= field.
TEAM_ID=$(security find-certificate -c "$SIGNING_IDENTITY" -p 2>/dev/null \
    | openssl x509 -noout -subject 2>/dev/null \
    | sed -n 's/.*\/OU=\([A-Z0-9]\{10\}\).*/\1/p' \
    | head -1)
if [[ -z "$TEAM_ID" ]]; then
    echo "error: could not extract Team ID from cert subject" >&2
    exit 1
fi

echo "    Identity:    $SIGNING_IDENTITY"
echo "    Team ID:     $TEAM_ID"
echo "    Profile:     $NOTARY_PROFILE"
echo

# ---- read version from project.yml ----
VERSION=$(grep -E '^\s*MARKETING_VERSION:' project.yml | head -1 | awk '{print $2}' | tr -d '"')
if [[ -z "$VERSION" ]]; then
    echo "error: could not extract MARKETING_VERSION from project.yml" >&2
    exit 1
fi
DATE=$(date +%Y-%m-%d)
DMG_NAME="PortyMcFolio-${VERSION}-${DATE}.dmg"
DMG_PATH="dist/${DMG_NAME}"

echo "==> Building PortyMcFolio ${VERSION} (signed + notarized)"
echo "    Output:      ${DMG_PATH}"
echo

# ---- regenerate Xcode project ----
if command -v xcodegen >/dev/null 2>&1; then
    echo "==> Regenerating Xcode project"
    xcodegen generate
    echo
fi

# ---- build Release with hardened runtime + secure timestamp ----
BUILD_DIR="${ROOT}/build"
DERIVED="${BUILD_DIR}/DerivedData"
APP_PATH="${DERIVED}/Build/Products/Release/PortyMcFolio.app"

rm -rf "$APP_PATH"

echo "==> Building Release configuration"
xcodebuild \
    -project PortyMcFolio.xcodeproj \
    -scheme PortyMcFolio \
    -configuration Release \
    -destination 'platform=macOS' \
    -derivedDataPath "${DERIVED}" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGNING_REQUIRED=YES \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    ENABLE_HARDENED_RUNTIME=YES \
    OTHER_CODE_SIGN_FLAGS="--timestamp --options runtime" \
    build 2>&1 | grep -E '(error:|warning: )' || true

if [[ ! -d "$APP_PATH" ]]; then
    echo "error: build did not produce ${APP_PATH}" >&2
    exit 1
fi
echo "    Built:       ${APP_PATH}"
echo

# ---- verify signature + hardened runtime ----
echo "==> Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP_PATH" 2>&1 | sed 's/^/    /'

# Capture once and substring-test — `grep -q` would race with codesign under
# `set -o pipefail` (grep closes stdin → codesign SIGPIPE → pipefail fails).
SIGN_INFO=$(codesign -d --verbose=4 "$APP_PATH" 2>&1)
if [[ "$SIGN_INFO" != *"flags=0x"*"runtime"* ]]; then
    echo "error: hardened runtime flag missing on built app" >&2
    exit 1
fi
echo "    Hardened runtime: enabled"

# Notarization rejects builds with get-task-allow (the debugger-attach
# entitlement). Catch it here instead of after a round-trip to Apple.
ENTITLEMENTS_XML=$(codesign -d --entitlements - --xml "$APP_PATH" 2>/dev/null || true)
if [[ "$ENTITLEMENTS_XML" == *"com.apple.security.get-task-allow"* ]]; then
    echo "error: built app has com.apple.security.get-task-allow — notarization will reject" >&2
    echo "       (Xcode injects this when CODE_SIGN_INJECT_BASE_ENTITLEMENTS != NO)" >&2
    exit 1
fi
echo "    Entitlements: clean (no get-task-allow)"
echo

# ---- stage + create DMG ----
STAGE=$(mktemp -d -t portymcfolio-dmg)
trap 'rm -rf "$STAGE"' EXIT

cp -R "$APP_PATH" "${STAGE}/"
ln -s /Applications "${STAGE}/Applications"

mkdir -p dist
rm -f "$DMG_PATH"

echo "==> Creating DMG"
hdiutil create \
    -volname "PortyMcFolio" \
    -srcfolder "$STAGE" \
    -ov \
    -format UDZO \
    -fs HFS+ \
    "$DMG_PATH" >/dev/null
echo "    Created:     ${DMG_PATH}"

echo "==> Signing DMG"
codesign --sign "$SIGNING_IDENTITY" --timestamp "$DMG_PATH" 2>&1 | sed 's/^/    /'
echo

# ---- notarize ----
echo "==> Submitting to Apple notarization (waits for result; usually 1–5 min)"
SUBMIT_JSON=$(xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait \
    --output-format json)

STATUS=$(echo "$SUBMIT_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("status",""))')
SUBMIT_ID=$(echo "$SUBMIT_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("id",""))')

if [[ "$STATUS" != "Accepted" ]]; then
    echo "error: notarization status = $STATUS (id: $SUBMIT_ID)" >&2
    echo "       fetching log..." >&2
    xcrun notarytool log "$SUBMIT_ID" --keychain-profile "$NOTARY_PROFILE" >&2 || true
    exit 1
fi
echo "    Status:      Accepted (submission $SUBMIT_ID)"
echo

# ---- staple + final verification ----
echo "==> Stapling notarization ticket"
xcrun stapler staple "$DMG_PATH" 2>&1 | sed 's/^/    /'
echo

echo "==> Final verification"
spctl --assess --type open --context context:primary-signature --verbose "$DMG_PATH" 2>&1 | sed 's/^/    /'
xcrun stapler validate "$DMG_PATH" 2>&1 | sed 's/^/    /'

SIZE=$(du -h "$DMG_PATH" | cut -f1)
echo
echo "✓ Done: ${DMG_PATH} (${SIZE})"
echo "  Recipients double-click the DMG, drag to Applications — no Gatekeeper warning."
