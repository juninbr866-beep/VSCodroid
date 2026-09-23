#!/usr/bin/env bash
set -euo pipefail

# Download Perl from Termux repo
# For toolchain packaging

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
PACK_ASSETS="$ROOT_DIR/android/toolchain_perl/src/main/assets"
WORK_DIR="$ROOT_DIR/toolchains/perl"

PERL_PACKAGES=(
    perl
    perl-rename
)

LIB_PACKAGES=(
    libandroid-utimes
)

echo "=== Downloading Perl toolchain ==="

. "$SCRIPT_DIR/lib/termux-packages.sh"

mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

termux_fetch_index
ALL_PACKAGES=("${PERL_PACKAGES[@]}" "${LIB_PACKAGES[@]}")
termux_resolve_packages resolved-perl.tsv "${ALL_PACKAGES[@]}"
PERL_VERSION="$(termux_pkg_version perl)"
echo "  Perl version: $PERL_VERSION"

termux_download_packages "${ALL_PACKAGES[@]}"

rm -rf "$WORK_DIR/extracted"
termux_extract_packages "${ALL_PACKAGES[@]}"

# Install to asset pack
echo ""
echo "Placing Perl toolchain in asset pack..."
rm -rf "$PACK_ASSETS/usr"
mkdir -p "$PACK_ASSETS/usr/bin"
mkdir -p "$PACK_ASSETS/usr/lib"
mkdir -p "$PACK_ASSETS/usr/lib/perl5"

PERL_BIN_DIR="extracted/perl/data/data/com.termux/files/usr/bin"
if [ -d "$PERL_BIN_DIR" ]; then
    for bin in "$PERL_BIN_DIR"/*; do
        [ -f "$bin" ] || continue
        name=$(basename "$bin")
        cp "$bin" "$PACK_ASSETS/usr/bin/$name"
        chmod +x "$PACK_ASSETS/usr/bin/$name"
    done
    echo "  Installed Perl binaries"
fi

# Install libraries
for pkg in "${LIB_PACKAGES[@]}"; do
    pkg_lib_dir="extracted/$pkg/data/data/com.termux/files/usr/lib"
    [ -d "$pkg_lib_dir" ] && cp -a "$pkg_lib_dir"/* "$PACK_ASSETS/usr/lib/" 2>/dev/null || true
done

# Perl lib directory
PERL_LIB_DIR="extracted/perl/data/data/com.termux/files/usr/lib/perl5"
[ -d "$PERL_LIB_DIR" ] && cp -a "$PERL_LIB_DIR"/* "$PACK_ASSETS/usr/lib/perl5/" 2>/dev/null || true

# Perl site/vendor libraries
for d in site_perl vendor_perl; do
    src="extracted/perl/data/data/com.termux/files/usr/lib/perl5/$d"
    [ -d "$src" ] && cp -a "$src" "$PACK_ASSETS/usr/lib/perl5/" 2>/dev/null || true
done

termux_copy_notices "$PACK_ASSETS/usr" "${ALL_PACKAGES[@]}"

# --- Write manifest ---
echo ""
echo "Writing toolchain_perl.json..."

BINARIES='['
FIRST_BIN=true
for cmd in "$PACK_ASSETS/usr/bin"/*; do
    [ -f "$cmd" ] || continue
    name="$(basename "$cmd")"
    [ "$FIRST_BIN" = true ] && FIRST_BIN=false || BINARIES+=','
    BINARIES+="\"usr/bin/$name\""
done
BINARIES+=']'

cat > "$PACK_ASSETS/toolchain_perl.json" << EOF
{
    "name": "perl",
    "displayName": "Perl",
    "version": "$PERL_VERSION",
    "binaries": $BINARIES,
    "env": {},
    "pathDirs": ["usr/bin"],
    "installRoot": "usr"
}
EOF
echo "  toolchain_perl.json written"

echo "=== Perl toolchain download complete ==="
