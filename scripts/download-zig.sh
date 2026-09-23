#!/usr/bin/env bash
set -euo pipefail

# Download Zig (single binary + lib) from ziglang.org
# Places files in the toolchain_zig asset pack module for Play Asset Delivery.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
PACK_ASSETS="$ROOT_DIR/android/toolchain_zig/src/main/assets"
WORK_DIR="$ROOT_DIR/toolchains/zig"

ZIG_VERSION="${ZIG_VERSION:-0.16.0}"
ZIG_SHA256="${ZIG_SHA256:-}"

echo "=== Downloading Zig $ZIG_VERSION ==="

mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# Fetch SHA256 from ziglang.org if not provided
if [ -z "$ZIG_SHA256" ]; then
    echo "Fetching checksums..."
    CHECKSUM_JSON=$(curl -sL "https://ziglang.org/download/index.json")
    ZIG_SHA256=$(echo "$CHECKSUM_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
ver = '$ZIG_VERSION'
if ver in data and 'aarch64-linux' in data[ver]:
    print(data[ver]['aarch64-linux'].get('shasum', ''))
" 2>/dev/null || true)
fi

TAR_NAME="zig-aarch64-linux-${ZIG_VERSION}.tar.xz"
TAR_URL="https://ziglang.org/download/${ZIG_VERSION}/${TAR_NAME}"
TAR_PATH="$WORK_DIR/${TAR_NAME}"

if [ -f "$TAR_PATH" ]; then
    echo "  Using cached $TAR_NAME"
else
    echo "  Downloading $TAR_NAME..."
    curl -L --fail --show-error -o "$TAR_PATH" "$TAR_URL"
fi

# Verify SHA256 if we have it
if [ -n "$ZIG_SHA256" ]; then
    ACTUAL_SHA=$(sha256sum "$TAR_PATH" | cut -d' ' -f1)
    if [ "$ACTUAL_SHA" != "$ZIG_SHA256" ]; then
        echo "ERROR: SHA256 mismatch" >&2
        echo "  Expected: $ZIG_SHA256" >&2
        echo "  Actual:   $ACTUAL_SHA" >&2
        exit 1
    fi
    echo "  SHA256 verified"
fi

# Extract
EXTRACT_DIR="$WORK_DIR/extracted"
rm -rf "$EXTRACT_DIR"
mkdir -p "$EXTRACT_DIR"
tar -xf "$TAR_PATH" -C "$EXTRACT_DIR" --strip-components=1

# Install to asset pack
echo ""
echo "Placing Zig toolchain in asset pack..."
rm -rf "$PACK_ASSETS/usr"
mkdir -p "$PACK_ASSETS/usr/bin"
mkdir -p "$PACK_ASSETS/usr/lib/zig"

cp "$EXTRACT_DIR/zig" "$PACK_ASSETS/usr/bin/zig"
chmod +x "$PACK_ASSETS/usr/bin/zig"

echo "  Installed zig ($(du -sh "$PACK_ASSETS/usr/bin/zig" | cut -f1))"

# Install lib (std library)
cp -r "$EXTRACT_DIR/lib"/* "$PACK_ASSETS/usr/lib/zig/"

echo "  Installed zig stdlib ($(du -sh "$PACK_ASSETS/usr/lib/zig" | cut -f1))"

# Copy licenses
if [ -f "$EXTRACT_DIR/LICENSE" ]; then
    mkdir -p "$PACK_ASSETS/usr/share/doc/zig"
    cp "$EXTRACT_DIR/LICENSE" "$PACK_ASSETS/usr/share/doc/zig/"
fi

# --- Write manifest ---
echo ""
echo "Writing toolchain_zig.json..."

BINARIES='['
FIRST_BIN=true
for cmd in "$PACK_ASSETS/usr/bin"/*; do
    [ -f "$cmd" ] || continue
    name="$(basename "$cmd")"
    [ "$FIRST_BIN" = true ] && FIRST_BIN=false || BINARIES+=','
    BINARIES+="\"usr/bin/$name\""
done
BINARIES+=']'

cat > "$PACK_ASSETS/toolchain_zig.json" << EOF
{
    "name": "zig",
    "displayName": "Zig",
    "version": "$ZIG_VERSION",
    "binaries": $BINARIES,
    "env": {},
    "pathDirs": ["usr/bin"],
    "installRoot": "usr"
}
EOF
echo "  toolchain_zig.json written"

echo "=== Zig toolchain download complete ==="
