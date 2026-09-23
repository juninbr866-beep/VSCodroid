#!/usr/bin/env bash
set -euo pipefail

# Download Bun (single binary) from GitHub releases
# Places files in the toolchain_bun asset pack module for Play Asset Delivery.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
PACK_ASSETS="$ROOT_DIR/android/toolchain_bun/src/main/assets"
WORK_DIR="$ROOT_DIR/toolchains/bun"

BUN_VERSION="${BUN_VERSION:-1.4.2}"
BUN_SHA256="${BUN_SHA256:-}"

echo "=== Downloading Bun $BUN_VERSION ==="

mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# Fetch release info to get SHA256 if not provided
if [ -z "$BUN_SHA256" ]; then
    echo "Fetching release info..."
    RELEASE_JSON=$(curl -sL "https://api.github.com/repos/oven-sh/bun/releases/tags/bun-v${BUN_VERSION}")
    BUN_SHA256=$(echo "$RELEASE_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for asset in data.get('assets', []):
    if asset['name'] == 'bun-linux-aarch64.zip':
        print(asset.get('digest', '').replace('sha256:', ''))
        break
" 2>/dev/null || true)
fi

ZIP_NAME="bun-linux-aarch64.zip"
ZIP_URL="https://github.com/oven-sh/bun/releases/download/bun-v${BUN_VERSION}/${ZIP_NAME}"
ZIP_PATH="$WORK_DIR/${ZIP_NAME}"

if [ -f "$ZIP_PATH" ]; then
    echo "  Using cached $ZIP_NAME"
else
    echo "  Downloading $ZIP_NAME..."
    curl -L --fail --show-error -o "$ZIP_PATH" "$ZIP_URL"
fi

# Verify SHA256 if we have it
if [ -n "$BUN_SHA256" ]; then
    ACTUAL_SHA=$(sha256sum "$ZIP_PATH" | cut -d' ' -f1)
    if [ "$ACTUAL_SHA" != "$BUN_SHA256" ]; then
        echo "ERROR: SHA256 mismatch" >&2
        echo "  Expected: $BUN_SHA256" >&2
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

# Find bun binary
BUN_BIN=$(find "$EXTRACT_DIR" -name "bun" -type f | head -1)
if [ -z "$BUN_BIN" ]; then
    echo "ERROR: bun binary not found in archive" >&2
    exit 1
fi

# Install to asset pack
echo ""
echo "Placing Bun toolchain in asset pack..."
rm -rf "$PACK_ASSETS/usr"
mkdir -p "$PACK_ASSETS/usr/bin"

cp "$BUN_BIN" "$PACK_ASSETS/usr/bin/bun"
chmod +x "$PACK_ASSETS/usr/bin/bun"

echo "  Installed bun ($(du -sh "$PACK_ASSETS/usr/bin/bun" | cut -f1))"

# Create bunx wrapper
cat > "$PACK_ASSETS/usr/bin/bunx" <<'EOF'
#!/system/bin/sh
exec "$PREFIX/bin/bun" x "$@"
EOF
chmod +x "$PACK_ASSETS/usr/bin/bunx"

# Copy licenses if any
if [ -f "$EXTRACT_DIR/LICENSE" ]; then
    mkdir -p "$PACK_ASSETS/usr/share/doc/bun"
    cp "$EXTRACT_DIR/LICENSE" "$PACK_ASSETS/usr/share/doc/bun/"
else
    mkdir -p "$PACK_ASSETS/usr/share/doc/bun"
    curl -L --fail --show-error \
        "https://raw.githubusercontent.com/oven-sh/bun/bun-v${BUN_VERSION}/LICENSE.md" \
        -o "$PACK_ASSETS/usr/share/doc/bun/LICENSE.md"
fi

# --- Write manifest ---
echo ""
echo "Writing toolchain_bun.json..."

BINARIES='['
FIRST_BIN=true
for cmd in "$PACK_ASSETS/usr/bin"/*; do
    [ -f "$cmd" ] || continue
    name="$(basename "$cmd")"
    [ "$FIRST_BIN" = true ] && FIRST_BIN=false || BINARIES+=','
    BINARIES+="\"usr/bin/$name\""
done
BINARIES+=']'

cat > "$PACK_ASSETS/toolchain_bun.json" << EOF
{
    "name": "bun",
    "displayName": "Bun",
    "version": "$BUN_VERSION",
    "binaries": $BINARIES,
    "env": {},
    "pathDirs": ["usr/bin"],
    "installRoot": "usr/bin"
}
EOF
echo "  toolchain_bun.json written"

echo "=== Bun toolchain download complete ==="
