#!/usr/bin/env bash
set -euo pipefail

# Download Lua 5.4 + Luajit from Termux repo
# For toolchain packaging

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
PACK_ASSETS="$ROOT_DIR/android/toolchain_lua/src/main/assets"
WORK_DIR="$ROOT_DIR/toolchains/lua"

LUA_PACKAGES=(
    lua54
    luajit
)

LIB_PACKAGES=(
    termux-licenses
    libandroid-support
)

echo "=== Downloading Lua toolchain ==="

. "$SCRIPT_DIR/lib/termux-packages.sh"

mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

termux_fetch_index
ALL_PACKAGES=("${LUA_PACKAGES[@]}" "${LIB_PACKAGES[@]}")
termux_resolve_packages resolved-lua.tsv "${ALL_PACKAGES[@]}"
LUA_VERSION="$(termux_pkg_version lua54)"
LUAJIT_VERSION="$(termux_pkg_version luajit)"
echo "  Lua version: $LUA_VERSION"
echo "  Luajit version: $LUAJIT_VERSION"

termux_download_packages "${ALL_PACKAGES[@]}"

rm -rf "$WORK_DIR/extracted"
termux_extract_packages "${ALL_PACKAGES[@]}"

# Install to asset pack
echo ""
echo "Placing Lua toolchain in asset pack..."
rm -rf "$PACK_ASSETS/usr"
mkdir -p "$PACK_ASSETS/usr/bin"
mkdir -p "$PACK_ASSETS/usr/lib"
mkdir -p "$PACK_ASSETS/usr/share/lua/5.4"
mkdir -p "$PACK_ASSETS/usr/lib/luarocks"

for pkg in "${LUA_PACKAGES[@]}"; do
    pkg_bin_dir="extracted/$pkg/data/data/com.termux/files/usr/bin"
    if [ -d "$pkg_bin_dir" ]; then
        for bin in "$pkg_bin_dir"/*; do
            [ -f "$bin" ] || continue
            name=$(basename "$bin")
            cp "$bin" "$PACK_ASSETS/usr/bin/$name"
            chmod +x "$PACK_ASSETS/usr/bin/$name"
        done
    fi
done
echo "  Installed Lua binaries: $(ls "$PACK_ASSETS/usr/bin/" | grep -E 'lua|luajit' | wc -l) files"

# Install libraries
for pkg in "${LIB_PACKAGES[@]}"; do
    pkg_lib_dir="extracted/$pkg/data/data/com.termux/files/usr/lib"
    [ -d "$pkg_lib_dir" ] && cp -a "$pkg_lib_dir"/* "$PACK_ASSETS/usr/lib/" 2>/dev/null || true
done

# Lua modules
LUA_SHARE_DIR="extracted/lua54/data/data/com.termux/files/usr/share/lua/5.4"
[ -d "$LUA_SHARE_DIR" ] && cp -a "$LUA_SHARE_DIR"/* "$PACK_ASSETS/usr/share/lua/5.4/" 2>/dev/null || true

# Luarocks support
LUAROCKS_DIR="extracted/luajit/data/data/com.termux/files/usr/lib/luarocks"
[ -d "$LUAROCKS_DIR" ] && cp -a "$LUAROCKS_DIR"/* "$PACK_ASSETS/usr/lib/luarocks/" 2>/dev/null || true

termux_copy_notices "$PACK_ASSETS/usr" "${ALL_PACKAGES[@]}"
for package in lua54 luajit; do
    if [ -f "$PACK_ASSETS/usr/share/doc/$package/copyright" ]; then
        cp "$PACK_ASSETS/usr/share/doc/$package/copyright" \
            "$PACK_ASSETS/usr/share/doc/$package/COPYING"
    fi
done

python3 - "$PACK_ASSETS/usr" "$ROOT_DIR/android/app/src/main/assets/usr" <<'PY'
import sys
from pathlib import Path

pack = Path(sys.argv[1])
base = Path(sys.argv[2])
for path in sorted(pack.rglob("*"), key=lambda p: len(p.parts), reverse=True):
    relative = path.relative_to(pack)
    other = base / relative
    if path.is_file() and other.is_file():
        path.unlink()
for path in sorted(pack.rglob("*"), key=lambda p: len(p.parts), reverse=True):
    if path.is_symlink() and not path.exists():
        path.unlink()
PY

LIBS_JSON="$(python3 - "$PACK_ASSETS/usr/lib" <<'PY'
import json
import sys
from pathlib import Path
root = Path(sys.argv[1])
print(json.dumps(sorted(p.name for p in root.iterdir() if p.is_file() and not p.is_symlink() and ".so" in p.name)))
PY
)"

# --- Write manifest ---
echo ""
echo "Writing toolchain_lua.json..."

BINARIES='['
FIRST_BIN=true
for cmd in "$PACK_ASSETS/usr/bin"/*; do
    [ -f "$cmd" ] || continue
    name="$(basename "$cmd")"
    [ "$FIRST_BIN" = true ] && FIRST_BIN=false || BINARIES+=','
    BINARIES+="\"usr/bin/$name\""
done
BINARIES+=']'

cat > "$PACK_ASSETS/toolchain_lua.json" << EOF
{
    "name": "lua",
    "displayName": "Lua",
    "version": "$LUA_VERSION",
    "binaries": $BINARIES,
    "env": {},
    "pathDirs": ["usr/bin"],
    "libs": $LIBS_JSON,
    "installRoot": "usr"
}
EOF
echo "  toolchain_lua.json written"

echo "=== Lua toolchain download complete ==="
