#!/usr/bin/env bash
#
# install.sh — Build PokeCard and install it on a connected iPhone, without
# opening Xcode. Handles project generation, code signing, and deployment.
#
# USAGE
#   ./install.sh                      # auto-detect team & device
#   POKECARD_TEAM_ID=ABCDE12345 ./install.sh
#   POKECARD_BUNDLE_ID=com.you.pokecard ./install.sh
#
# REQUIREMENTS (the script checks these and tells you what's missing)
#   • macOS with full Xcode installed (xcodebuild, xcrun, devicectl).
#   • An Apple ID added to Xcode (Xcode ▸ Settings ▸ Accounts). A free Apple ID
#     works but the app expires after 7 days — just re-run this script.
#   • An iPhone connected via USB (or paired over Wi-Fi), unlocked, trusting
#     this Mac, with Developer Mode enabled (Settings ▸ Privacy & Security ▸
#     Developer Mode) on iOS 16+.
#   • Homebrew (used to auto-install XcodeGen if absent). Optional otherwise.
#
# WHAT IT DOES
#   1. Verifies the toolchain.
#   2. Generates PokeCard.xcodeproj from project.yml via XcodeGen.
#   3. Resolves your Apple Developer Team ID (auto-detect or env var).
#   4. Builds a signed .app for your device (Debug, device SDK).
#   5. Installs it onto the connected iPhone with `xcrun devicectl`.
#
set -euo pipefail

# ---------- pretty output ----------
BOLD=$'\033[1m'; RED=$'\033[31m'; GRN=$'\033[32m'; YLW=$'\033[33m'; CYN=$'\033[36m'; RST=$'\033[0m'
step() { echo "${CYN}${BOLD}==>${RST} ${BOLD}$*${RST}"; }
info() { echo "    $*"; }
ok()   { echo "${GRN}  ✓${RST} $*"; }
warn() { echo "${YLW}  !${RST} $*"; }
die()  { echo "${RED}${BOLD}✗ $*${RST}" >&2; exit 1; }

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(pwd)"

# ---------- config (overridable via env) ----------
APP_NAME="PokeCard"
SCHEME="PokeCard"
CONFIGURATION="${POKECARD_CONFIG:-Debug}"
BUNDLE_ID="${POKECARD_BUNDLE_ID:-}"
BUNDLE_ID_PREFIX="${POKECARD_BUNDLE_ID_PREFIX:-com.example}"
TEAM_ID="${POKECARD_TEAM_ID:-}"
DERIVED_DATA="${PROJECT_DIR}/.build/DerivedData"

# =====================================================================
step "1/6  Checking the toolchain"
# =====================================================================
command -v xcodebuild >/dev/null 2>&1 || die "xcodebuild not found. Install full Xcode from the App Store, then run: sudo xcode-select -s /Applications/Xcode.app"
XCODE_PATH="$(xcode-select -p 2>/dev/null || true)"
case "$XCODE_PATH" in
  *CommandLineTools*) die "xcode-select points to the Command Line Tools, not full Xcode.\n     Run: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" ;;
esac
ok "Xcode: $(xcodebuild -version | head -1)"

command -v xcrun >/dev/null 2>&1 || die "xcrun not found."
if xcrun devicectl --version >/dev/null 2>&1; then
  HAS_DEVICECTL=1; ok "devicectl available"
else
  HAS_DEVICECTL=0; warn "devicectl not available; will try ios-deploy fallback"
fi

# ---------- XcodeGen ----------
if ! command -v xcodegen >/dev/null 2>&1; then
  warn "XcodeGen not found."
  if command -v brew >/dev/null 2>&1; then
    step "    Installing XcodeGen via Homebrew"
    brew install xcodegen
  else
    die "XcodeGen is required to generate the Xcode project and Homebrew is not installed.\n     Install Homebrew (https://brew.sh) or XcodeGen manually, then re-run."
  fi
fi
ok "XcodeGen: $(xcodegen --version 2>/dev/null | head -1)"

# =====================================================================
step "2/6  Resolving signing identity (Team ID)"
# =====================================================================
if [[ -z "$TEAM_ID" ]]; then
  # Try to auto-detect a development team from installed signing identities.
  DETECTED="$(security find-identity -v -p codesigning 2>/dev/null \
    | grep -Eo 'Apple Development: .*\(([A-Z0-9]{10})\)' \
    | grep -Eo '\(([A-Z0-9]{10})\)' | tr -d '()' | head -1 || true)"
  if [[ -n "$DETECTED" ]]; then
    TEAM_ID="$DETECTED"
    info "Auto-detected Team ID from your signing certificate: ${BOLD}${TEAM_ID}${RST}"
  fi
fi

if [[ -z "$TEAM_ID" ]]; then
  cat <<EOF
${YLW}  !${RST} Could not auto-detect your Apple Developer Team ID.
    Open Xcode ▸ Settings ▸ Accounts, add your Apple ID, then find the Team ID
    (Manage Certificates, or developer.apple.com ▸ Membership), and run:

        POKECARD_TEAM_ID=XXXXXXXXXX ./install.sh

EOF
  die "Team ID required for code signing."
fi
ok "Using Team ID: $TEAM_ID"

# Default bundle id derives from the prefix if not provided.
if [[ -z "$BUNDLE_ID" ]]; then
  BUNDLE_ID="${BUNDLE_ID_PREFIX}.pokecard"
fi
info "Bundle identifier: ${BOLD}${BUNDLE_ID}${RST}"
info "(Use a unique bundle id you own if signing with a paid account.)"

# =====================================================================
step "3/6  Generating ${APP_NAME}.xcodeproj"
# =====================================================================
export POKECARD_BUNDLE_ID="$BUNDLE_ID"
export POKECARD_BUNDLE_ID_PREFIX="$BUNDLE_ID_PREFIX"
export POKECARD_TEAM_ID="$TEAM_ID"
xcodegen generate --spec project.yml
ok "Project generated"

# =====================================================================
step "4/6  Finding a connected iPhone"
# =====================================================================
DEVICE_ID=""
DEVICE_NAME=""
if [[ "$HAS_DEVICECTL" == "1" ]]; then
  # Parse devicectl JSON for the first connected device.
  TMP_JSON="$(mktemp)"
  if xcrun devicectl list devices --json-output "$TMP_JSON" >/dev/null 2>&1; then
    DEVICE_ID="$(/usr/bin/python3 - "$TMP_JSON" <<'PY'
import json, sys
try:
    data = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
for d in data.get("result", {}).get("devices", []):
    conn = d.get("connectionProperties", {})
    if conn.get("tunnelState") in ("connected", "available") or \
       d.get("deviceProperties", {}).get("developerModeStatus") is not None:
        print(d.get("hardwareProperties", {}).get("udid", ""))
        break
PY
)"
    DEVICE_NAME="$(/usr/bin/python3 - "$TMP_JSON" "$DEVICE_ID" <<'PY'
import json, sys
try:
    data = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
udid = sys.argv[2] if len(sys.argv) > 2 else ""
for d in data.get("result", {}).get("devices", []):
    if d.get("hardwareProperties", {}).get("udid", "") == udid:
        print(d.get("deviceProperties", {}).get("name", "iPhone"))
        break
PY
)"
  fi
  rm -f "$TMP_JSON"
fi

if [[ -z "$DEVICE_ID" ]]; then
  cat <<EOF
${YLW}  !${RST} No connected iPhone detected.
    • Plug your iPhone in via USB (or pair over Wi-Fi).
    • Unlock it and tap "Trust This Computer".
    • Enable Developer Mode: Settings ▸ Privacy & Security ▸ Developer Mode.
    Then re-run ./install.sh
EOF
  die "No device found."
fi
ok "Device: ${DEVICE_NAME:-iPhone} ($DEVICE_ID)"

# =====================================================================
step "5/6  Building signed ${APP_NAME}.app for the device"
# =====================================================================
set -x
xcodebuild \
  -project "${APP_NAME}.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "id=$DEVICE_ID" \
  -derivedDataPath "$DERIVED_DATA" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Automatic \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  build
set +x

APP_PATH="$(/usr/bin/find "$DERIVED_DATA/Build/Products/${CONFIGURATION}-iphoneos" -maxdepth 1 -name '*.app' -print -quit 2>/dev/null || true)"
[[ -n "$APP_PATH" && -d "$APP_PATH" ]] || die "Build succeeded but the .app was not found under DerivedData."
ok "Built: $APP_PATH"

# =====================================================================
step "6/6  Installing onto the iPhone"
# =====================================================================
if [[ "$HAS_DEVICECTL" == "1" ]]; then
  xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH"
elif command -v ios-deploy >/dev/null 2>&1; then
  ios-deploy --id "$DEVICE_ID" --bundle "$APP_PATH"
else
  die "No installer available. Install one with: brew install ios-deploy"
fi

echo
echo "${GRN}${BOLD}✅ Done!${RST} ${APP_NAME} is installed on ${DEVICE_NAME:-your iPhone}."
echo
echo "${BOLD}First launch:${RST}"
echo "  • If the app won't open, trust the developer certificate on the device:"
echo "    Settings ▸ General ▸ VPN & Device Management ▸ (your Apple ID) ▸ Trust."
echo "  • Free Apple IDs: the app stops working after 7 days — just re-run this script."
echo "  • Google Sign-In needs GoogleService-Info.plist + the REVERSED_CLIENT_ID"
echo "    in Info.plist (see README). Email sign-in needs Firebase configured."
