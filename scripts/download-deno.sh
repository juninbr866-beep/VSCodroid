#!/usr/bin/env bash
set -euo pipefail

# Download Deno (single binary) from GitHub releases
# Places files in the toolchain_deno asset pack module for Play Asset Delivery.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
PACK_ASSETS="$ROOT_DIR/android/toolchain_deno/src/main/assets"
WORK_DIR="$ROOT_DIR/toolchains/deno"

DENO_VERSION="${DENO_VERSION:-2.9.6}"
DENO_SHA256="${DENO_SHA256:-}"

echo "=== Downloading Deno $DENO_VERSION ==="

mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# Fetch release info to get SHA256 if not provided
if [ -z "$DENO_SHA256" ]; then
    echo "Fetching release info..."
    RELEASE_JSON=$(curl -sL "https://api.github.com/repos/denoland/deno/releases/tags/v${DENO_VERSION}")
    DENO_SHA256=$(echo "$RELEASE_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for asset in data.get('assets', []):
    if asset['name'] == 'deno-aarch64-unknown-linux-gnu.zip':
        print(asset.get('digest', '').replace('sha256:', ''))
        break
" 2>/dev/null || true)
fi

ZIP_NAME="deno-aarch64-unknown-linux-gnu.zip"
ZIP_URL="https://github.com/denoland/deno/releases/download/v${DENO_VERSION}/${ZIP_NAME}"
ZIP_PATH="$WORK_DIR/${ZIP_NAME}"

if [ -f "$ZIP_PATH" ]; then
    echo "  Using cached $ZIP_NAME"
else
    echo "  Downloading $ZIP_NAME..."
    curl -L --fail --show-error -o "$ZIP_PATH" "$ZIP_URL"
fi

# Verify SHA256 if we have it
if [ -n "$DENO_SHA256" ]; then
    ACTUAL_SHA=$(sha256sum "$ZIP_PATH" | cut -d' ' -f1)
    if [ "$ACTUAL_SHA" != "$DENO_SHA256" ]; then
        echo "ERROR: SHA256 mismatch" >&2
        echo "  Expected: $DENO_SHA256" >&2
        echo "  Actual:   $ACTUAL_SHA" >&2
        exit 1
    fi
    echo "  SHA256 verified"
fi

# Extract
EXTRACT_DIR="$WORK_DIR/extracted"
rm -rf "$EXTRACT_DIR"
mkdir -p "$EXTRACT_DIR"
unzip -q "$ZIP_PATH" -d "$EXTRACT_DIR"

# Find deno binary
DENO_BIN=$(find "$EXTRACT_DIR" -name "deno" -type f | head -1)
if [ -z "$DENO_BIN" ]; then
    echo "ERROR: deno binary not found in archive" >&2
    exit 1
fi

# Install to asset pack
echo ""
echo "Placing Deno toolchain in asset pack..."
rm -rf "$PACK_ASSETS/usr"
mkdir -p "$PACK_ASSETS/usr/bin"

cp "$DENO_BIN" "$PACK_ASSETS/usr/bin/deno"
chmod +x "$PACK_ASSETS/usr/bin/deno"

echo "  Installed deno ($(du -sh "$PACK_ASSETS/usr/bin/deno" | cut -f1))"

# Copy licenses
if [ -f "$EXTRACT_DIR/LICENSE" ]; then
    mkdir -p "$PACK_ASSETS/usr/share/doc/deno"
    cp "$EXTRACT_DIR/LICENSE" "$PACK_ASSETS/usr/share/doc/deno/"
fi

# --- Write manifest ---
echo ""
echo "Writing toolchain_deno.json..."

BINARIES='['
FIRST_BIN=true
for cmd in "$PACK_ASSETS/usr/bin"/*; do
    [ -f "$cmd" ] || continue
    name="$(basename "$cmd")"
    [ "$FIRST_BIN" = true ] && FIRST_BIN=false || BINARIES+=','
    BINARIES+="\"usr/bin/$name\""
done
BINARIES+=']'

cat > "$PACK_ASSETS/toolchain_deno.json" << EOF
{
    "name": "deno",
    "displayName": "Deno",
    "version": "$DENO_VERSION",
    "binaries": $BINARIES,
    "env": {},
    "pathDirs": ["usr/bin"],
    "installRoot": "usr/bin"
}
EOF
echo "  toolchain_deno.json written"

echo "=== Deno toolchain download complete ==="
