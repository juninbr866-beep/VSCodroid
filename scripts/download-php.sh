#!/usr/bin/env bash
set -euo pipefail

# Download PHP + extensions from Termux repo
# For toolchain packaging

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
PACK_ASSETS="$ROOT_DIR/android/toolchain_php/src/main/assets"
WORK_DIR="$ROOT_DIR/toolchains/php"

# PHP packages from Termux
PHP_PACKAGES=(
    php
    php-fpm
    php-gd
    php-imagick
    php-ldap
    php-pgsql
    php-redis
    php-sodium
    php-apcu
)

LIB_PACKAGES=(
    capstone libandroid-glob libandroid-support libbz2 libc++
    libcurl libffi libgmp libiconv libicu libresolv-wrapper
    libsqlite libxml2 libxslt libzip oniguruma openssl pcre2
    readline tidy zlib
    termux-licenses
)

echo "=== Downloading PHP toolchain ==="

. "$SCRIPT_DIR/lib/termux-packages.sh"

mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

termux_fetch_index

ALL_PACKAGES=("${PHP_PACKAGES[@]}" "${LIB_PACKAGES[@]}")
termux_resolve_packages resolved-php.tsv "${ALL_PACKAGES[@]}"
PHP_VERSION="$(termux_pkg_version php)"
echo "  PHP version: $PHP_VERSION"

termux_download_packages "${ALL_PACKAGES[@]}"

rm -rf "$WORK_DIR/extracted"
termux_extract_packages "${ALL_PACKAGES[@]}"

# Install to asset pack
echo ""
echo "Placing PHP toolchain in asset pack..."
rm -rf "$PACK_ASSETS/usr"
mkdir -p "$PACK_ASSETS/usr/bin"
mkdir -p "$PACK_ASSETS/usr/lib"
mkdir -p "$PACK_ASSETS/usr/lib/php"
mkdir -p "$PACK_ASSETS/usr/etc/php"

PHP_BIN_DIR="extracted/php/data/data/com.termux/files/usr/bin"
if [ -d "$PHP_BIN_DIR" ]; then
    for bin in "$PHP_BIN_DIR"/*; do
        [ -f "$bin" ] || continue
        name=$(basename "$bin")
        cp "$bin" "$PACK_ASSETS/usr/bin/$name"
        chmod +x "$PACK_ASSETS/usr/bin/$name"
    done
    echo "  Installed PHP binaries ($(ls "$PACK_ASSETS/usr/bin/" | grep -c php) files)"
fi

# Install libraries
for pkg in "${LIB_PACKAGES[@]}"; do
    pkg_lib_dir="extracted/$pkg/data/data/com.termux/files/usr/lib"
    if [ -d "$pkg_lib_dir" ]; then
        cp -a "$pkg_lib_dir"/* "$PACK_ASSETS/usr/lib/" 2>/dev/null || true
    fi
done
echo "  Installed PHP libraries"

# Install PHP extensions/modules
PHP_EXT_DIR="extracted/php/data/data/com.termux/files/usr/lib/php"
if [ -d "$PHP_EXT_DIR" ]; then
    cp -a "$PHP_EXT_DIR"/* "$PACK_ASSETS/usr/lib/php/" 2>/dev/null || true
    echo "  Installed PHP extensions"
fi

# Install PHP config/templates
PHP_ETC_DIR="extracted/php/data/data/com.termux/files/usr/etc/php"
if [ -d "$PHP_ETC_DIR" ]; then
    cp -a "$PHP_ETC_DIR"/* "$PACK_ASSETS/usr/etc/php/" 2>/dev/null || true
fi

# Copy notices
termux_copy_notices "$PACK_ASSETS/usr" "${ALL_PACKAGES[@]}"

# --- Write manifest ---
echo ""
echo "Writing toolchain_php.json..."

BINARIES='['
FIRST_BIN=true
for cmd in "$PACK_ASSETS/usr/bin"/*; do
    [ -f "$cmd" ] || continue
    name="$(basename "$cmd")"
    [ "$FIRST_BIN" = true ] && FIRST_BIN=false || BINARIES+=','
    BINARIES+="\"usr/bin/$name\""
done
BINARIES+=']'

cat > "$PACK_ASSETS/toolchain_php.json" << EOF
{
    "name": "php",
    "displayName": "PHP 8.5",
    "version": "$PHP_VERSION",
    "binaries": $BINARIES,
    "env": {},
    "pathDirs": ["usr/bin"],
    "installRoot": "usr"
}
EOF
echo "  toolchain_php.json written"

echo "=== PHP toolchain download complete ==="
