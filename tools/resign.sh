#!/bin/bash
#
# resign.sh — Re-sign an already-injected IPA
#
# Usage:
#   ./resign.sh <input.ipa> [identity] [output.ipa]
#
#   identity: A codesign identity string, or "-" for ad-hoc (default).
#             Use "ldid" to force ldid-based signing instead of codesign.
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
    echo "  $0 <input.ipa> [identity] [output.ipa]"
    echo ""
    echo "Arguments:"
    echo "  input.ipa    Path to the IPA to re-sign"
    echo "  identity     (Optional) Signing identity. Options:"
    echo "                 -       Ad-hoc signing with codesign (default)"
    echo "                 ldid    Use ldid for ad-hoc signing"
    echo "                 <id>    A codesign identity (name or SHA-1 hash)"
    echo "  output.ipa   (Optional) Output IPA path. Defaults to <input>-resigned.ipa"
    echo ""
    echo "Examples:"
    echo "  $0 agario-modded.ipa                    # Ad-hoc with codesign"
    echo "  $0 agario-modded.ipa ldid                # Ad-hoc with ldid"
    echo "  $0 agario-modded.ipa \"Apple Development\"  # Dev certificate"
    exit 1
}

# ── Validate arguments ──────────────────────────────────────────────────────
if [[ $# -lt 1 ]]; then
    usage
fi

INPUT_IPA="$1"
IDENTITY="${2:--}"
OUTPUT_IPA="${3:-}"

if [[ ! -f "$INPUT_IPA" ]]; then
    error "IPA not found: $INPUT_IPA"
fi

# Default output name
if [[ -z "$OUTPUT_IPA" ]]; then
    BASENAME="$(basename "$INPUT_IPA" .ipa)"
    OUTPUT_DIR="$(dirname "$INPUT_IPA")"
    OUTPUT_IPA="${OUTPUT_DIR}/${BASENAME}-resigned.ipa"
fi

# ── Determine signing method ────────────────────────────────────────────────
USE_LDID=false
if [[ "$IDENTITY" == "ldid" ]]; then
    USE_LDID=true
    if ! command -v ldid &>/dev/null; then
        error "ldid not found in PATH"
    fi
    info "Signing method: ${BOLD}ldid${RESET} (ad-hoc)"
else
    if ! command -v codesign &>/dev/null; then
        error "codesign not found in PATH"
    fi
    if [[ "$IDENTITY" == "-" ]]; then
        info "Signing method: ${BOLD}codesign${RESET} (ad-hoc)"
    else
        info "Signing method: ${BOLD}codesign${RESET} with identity ${BOLD}${IDENTITY}${RESET}"
    fi
fi

# ── Create temp directory ───────────────────────────────────────────────────
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
info "Working directory: $WORK_DIR"

# ── Unzip IPA ────────────────────────────────────────────────────────────────
info "Extracting IPA..."
unzip -q "$INPUT_IPA" -d "$WORK_DIR"

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

FRAMEWORKS_DIR="$APP_DIR/Frameworks"

# ── Sign ─────────────────────────────────────────────────────────────────────
info "Signing all binaries..."

sign_with_ldid() {
    local target="$1"
    ldid -S "$target"
}

sign_with_codesign() {
    local target="$1"
    local is_dir="$2"
    if [[ "$is_dir" == "true" ]]; then
        codesign --force --deep --sign "$IDENTITY" "$target"
    else
        codesign --force --sign "$IDENTITY" "$target"
    fi
}

SIGNED_COUNT=0

# Sign frameworks and dylibs
if [[ -d "$FRAMEWORKS_DIR" ]]; then
    while IFS= read -r -d '' item; do
        if $USE_LDID; then
            if [[ -d "$item" ]]; then
                # Framework bundle — sign the inner binary
                fw_binary="$item/$(basename "$item" .framework)"
                if [[ -f "$fw_binary" ]]; then
                    sign_with_ldid "$fw_binary"
                    ((SIGNED_COUNT++))
                fi
            else
                sign_with_ldid "$item"
                ((SIGNED_COUNT++))
            fi
        else
            if [[ -d "$item" ]]; then
                sign_with_codesign "$item" "true"
            else
                sign_with_codesign "$item" "false"
            fi
            ((SIGNED_COUNT++))
        fi
    done < <(find "$FRAMEWORKS_DIR" \( -name '*.dylib' -o -name '*.framework' \) -print0)
fi

# Sign the main binary
if $USE_LDID; then
    sign_with_ldid "$MAIN_BINARY"
else
    sign_with_codesign "$MAIN_BINARY" "false"
fi
((SIGNED_COUNT++))

ok "Signed ${SIGNED_COUNT} item(s)"

# ── Re-package IPA ───────────────────────────────────────────────────────────
info "Re-packaging IPA..."
pushd "$WORK_DIR" >/dev/null
zip -qr "$OUTPUT_IPA" Payload/
popd >/dev/null

ok "Re-signed IPA created: ${BOLD}${OUTPUT_IPA}${RESET}"
echo ""
echo -e "${GREEN}${BOLD}Done!${RESET} Install with your preferred sideloading tool."
