#!/bin/bash
#
# inject.sh — Inject XRD.dylib into an Agar.io IPA
#
# Usage:
#   ./inject.sh <original.ipa> <XRD.dylib> [output.ipa]
#
# Requirements:
#   - optool or insert_dylib (for adding load commands)
#   - ldid or codesign (for ad-hoc signing)
#   - zip / unzip
#

set -euo pipefail

# ── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

info()  { echo -e "${CYAN}[*]${RESET} $*"; }
ok()    { echo -e "${GREEN}[+]${RESET} $*"; }
warn()  { echo -e "${YELLOW}[!]${RESET} $*"; }
error() { echo -e "${RED}[-]${RESET} $*"; exit 1; }

# ── Usage ────────────────────────────────────────────────────────────────────
usage() {
    echo -e "${BOLD}Usage:${RESET}"
    echo "  $0 <original.ipa> <XRD.dylib> [output.ipa]"
    echo ""
    echo "Arguments:"
    echo "  original.ipa    Path to the original Agar.io IPA file"
    echo "  XRD.dylib   Path to the compiled tweak dylib"
    echo "  output.ipa      (Optional) Output IPA path. Defaults to <original>-modded.ipa"
    echo ""
    echo "Requirements:"
    echo "  - optool or insert_dylib"
    echo "  - ldid or codesign"
    echo "  - zip, unzip"
    exit 1
}

# ── Validate arguments ──────────────────────────────────────────────────────
if [[ $# -lt 2 ]]; then
    usage
fi

ORIGINAL_IPA="$1"
DYLIB_PATH="$2"
OUTPUT_IPA="${3:-}"

if [[ ! -f "$ORIGINAL_IPA" ]]; then
    error "IPA not found: $ORIGINAL_IPA"
fi

if [[ ! -f "$DYLIB_PATH" ]]; then
    error "Dylib not found: $DYLIB_PATH"
fi

# Default output name
if [[ -z "$OUTPUT_IPA" ]]; then
    BASENAME="$(basename "$ORIGINAL_IPA" .ipa)"
    OUTPUT_DIR="$(dirname "$ORIGINAL_IPA")"
    OUTPUT_IPA="${OUTPUT_DIR}/${BASENAME}-modded.ipa"
fi

# ── Locate injection tool ───────────────────────────────────────────────────
INJECT_TOOL=""
if command -v optool &>/dev/null; then
    INJECT_TOOL="optool"
elif command -v insert_dylib &>/dev/null; then
    INJECT_TOOL="insert_dylib"
else
    error "Neither optool nor insert_dylib found in PATH. Install one of them first."
fi
info "Using injection tool: ${BOLD}${INJECT_TOOL}${RESET}"

# Signing is left to the user's tool (KSign, Sideloadly, AltStore, etc.)

# ── Create temp directory ───────────────────────────────────────────────────
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
info "Working directory: $WORK_DIR"

# ── Unzip IPA ────────────────────────────────────────────────────────────────
info "Extracting IPA..."
unzip -q "$ORIGINAL_IPA" -d "$WORK_DIR"

# Locate the .app bundle
APP_DIR="$(find "$WORK_DIR/Payload" -maxdepth 1 -name '*.app' -type d | head -n 1)"
if [[ -z "$APP_DIR" ]]; then
    error "No .app bundle found in Payload/"
fi

APP_NAME="$(basename "$APP_DIR" .app)"
info "Found app bundle: ${BOLD}${APP_NAME}${RESET}"

# ── Determine main binary ───────────────────────────────────────────────────
MAIN_BINARY="$APP_DIR/$APP_NAME"
if [[ ! -f "$MAIN_BINARY" ]]; then
    # Try reading CFBundleExecutable from Info.plist
    if command -v plutil &>/dev/null; then
        EXEC_NAME="$(plutil -p "$APP_DIR/Info.plist" 2>/dev/null | grep CFBundleExecutable | awk -F'"' '{print $4}')"
    elif command -v /usr/libexec/PlistBuddy &>/dev/null; then
        EXEC_NAME="$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$APP_DIR/Info.plist" 2>/dev/null)"
    else
        EXEC_NAME=""
    fi

    if [[ -n "$EXEC_NAME" && -f "$APP_DIR/$EXEC_NAME" ]]; then
        MAIN_BINARY="$APP_DIR/$EXEC_NAME"
    else
        error "Could not locate main binary in $APP_DIR"
    fi
fi
info "Main binary: $(basename "$MAIN_BINARY")"

# ── Create Frameworks directory if needed ────────────────────────────────────
FRAMEWORKS_DIR="$APP_DIR/Frameworks"
mkdir -p "$FRAMEWORKS_DIR"

# ── Copy dylib ───────────────────────────────────────────────────────────────
DYLIB_NAME="$(basename "$DYLIB_PATH")"
info "Copying ${BOLD}${DYLIB_NAME}${RESET} into Frameworks/"
cp "$DYLIB_PATH" "$FRAMEWORKS_DIR/$DYLIB_NAME"

# ── Copy CydiaSubstrate.framework if not already present ─────────────────────
SUBSTRATE_SRC=""
if [[ -d "${THEOS:-}/vendor/lib/CydiaSubstrate.framework" ]]; then
    SUBSTRATE_SRC="${THEOS}/vendor/lib/CydiaSubstrate.framework"
elif [[ -d "/Library/Frameworks/CydiaSubstrate.framework" ]]; then
    SUBSTRATE_SRC="/Library/Frameworks/CydiaSubstrate.framework"
fi

if [[ -n "$SUBSTRATE_SRC" ]]; then
    if [[ ! -d "$FRAMEWORKS_DIR/CydiaSubstrate.framework" ]]; then
        info "Copying CydiaSubstrate.framework into Frameworks/"
        cp -R "$SUBSTRATE_SRC" "$FRAMEWORKS_DIR/"
    else
        ok "CydiaSubstrate.framework already present"
    fi
else
    warn "CydiaSubstrate.framework not found on this system. Make sure it is bundled manually."
fi

# ── Inject load command ──────────────────────────────────────────────────────
LOAD_PATH="@rpath/XRD.dylib"
info "Injecting load command: ${BOLD}${LOAD_PATH}${RESET}"

if [[ "$INJECT_TOOL" == "optool" ]]; then
    optool install -c load -p "$LOAD_PATH" -t "$MAIN_BINARY"
elif [[ "$INJECT_TOOL" == "insert_dylib" ]]; then
    insert_dylib --inplace --no-strip-codesig "$LOAD_PATH" "$MAIN_BINARY"
fi
ok "Load command injected"

# ── Strip all code signatures (let the user's signing tool handle it) ────────
info "Stripping code signatures for clean re-signing..."

# Remove _CodeSignature dirs from all frameworks and the app itself
find "$APP_DIR" -name '_CodeSignature' -type d -exec rm -rf {} + 2>/dev/null || true

# Remove embedded.mobileprovision if present (KSign/Sideloadly inject their own)
rm -f "$APP_DIR/embedded.mobileprovision"

ok "Signatures stripped — IPA ready for KSign/Sideloadly/AltStore signing"

# ── Re-package IPA ───────────────────────────────────────────────────────────
info "Re-packaging IPA..."
pushd "$WORK_DIR" >/dev/null
zip -qr "$OUTPUT_IPA" Payload/
popd >/dev/null

ok "Modded IPA created: ${BOLD}${OUTPUT_IPA}${RESET}"
echo ""
echo -e "${GREEN}${BOLD}Done!${RESET} Install the IPA with your preferred sideloading tool."
echo -e "  - TrollStore, AltStore, Sideloadly, etc."
