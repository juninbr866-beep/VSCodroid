#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
PACK_ASSETS="$ROOT_DIR/android/toolchain_dart/src/main/assets"
WORK_DIR="$ROOT_DIR/toolchains/dart"
PACKAGES=(dart termux-licenses)

. "$SCRIPT_DIR/lib/termux-packages.sh"

mkdir -p "$WORK_DIR"
cd "$WORK_DIR"
termux_fetch_index
termux_resolve_packages resolved-dart.tsv "${PACKAGES[@]}"
DART_VERSION="$(termux_pkg_version dart)"
termux_download_packages "${PACKAGES[@]}"
rm -rf extracted
termux_extract_packages "${PACKAGES[@]}"

DART_USR="$WORK_DIR/extracted/dart/data/data/com.termux/files/usr"
rm -rf "$PACK_ASSETS/usr"
mkdir -p "$PACK_ASSETS/usr/lib/dart" "$PACK_ASSETS/usr/etc" "$PACK_ASSETS/usr/share"
cp -a "$DART_USR/lib/dart-sdk/." "$PACK_ASSETS/usr/lib/dart/"
rm -f "$PACK_ASSETS/usr/lib/dart/lib/_internal/vm_platform_strong.dill"
cp "$DART_USR/lib/dart-sdk/lib/_internal/vm_platform.dill" \
    "$PACK_ASSETS/usr/lib/dart/lib/_internal/vm_platform_strong.dill"
[ ! -d "$DART_USR/etc" ] || cp -RL "$DART_USR/etc/." "$PACK_ASSETS/usr/etc/"
[ ! -d "$DART_USR/share" ] || cp -RL "$DART_USR/share/." "$PACK_ASSETS/usr/share/"
termux_copy_notices "$PACK_ASSETS/usr" "${PACKAGES[@]}"

for binary in dart dartaotruntime dartvm; do
    python3 "$SCRIPT_DIR/verify-android-elf.py" \
        "$PACK_ASSETS/usr/lib/dart/bin/$binary" \
        --lib-dir "$PACK_ASSETS/usr/lib"
done

cat > "$PACK_ASSETS/toolchain_dart.json" << EOF
{
    "name": "dart",
    "displayName": "Dart",
    "version": "$DART_VERSION",
    "binaries": [
        "usr/lib/dart/bin/dart",
        "usr/lib/dart/bin/dartaotruntime",
        "usr/lib/dart/bin/dartvm"
    ],
    "env": {
        "DART_SDK": "\$FILESDIR/usr/lib/dart"
    },
    "pathDirs": ["usr/lib/dart/bin"],
    "installRoot": "usr/lib/dart"
}
EOF

echo "Dart $DART_VERSION: $(du -sh "$PACK_ASSETS/usr" | cut -f1)"
