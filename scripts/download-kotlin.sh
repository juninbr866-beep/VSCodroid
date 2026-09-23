#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
PACK_ASSETS="$ROOT_DIR/android/toolchain_kotlin/src/main/assets"
WORK_DIR="$ROOT_DIR/toolchains/kotlin"
KOTLIN_VERSION="${KOTLIN_VERSION:-2.4.20}"
KOTLIN_SHA256="${KOTLIN_SHA256:-59e9ca74c7904ef2c122b12114937673ccce68de820a663f0ed66ccf8799e0b7}"
PACKAGES=(openjdk-21 libandroid-shmem termux-licenses)

. "$SCRIPT_DIR/lib/termux-packages.sh"

mkdir -p "$WORK_DIR/jdk" "$WORK_DIR/compiler"
(
    cd "$WORK_DIR/jdk"
    WORK_DIR="$WORK_DIR/jdk" termux_fetch_index
    WORK_DIR="$WORK_DIR/jdk" termux_resolve_packages resolved-jdk.tsv "${PACKAGES[@]}"
    WORK_DIR="$WORK_DIR/jdk" termux_download_packages "${PACKAGES[@]}"
    rm -rf extracted
    WORK_DIR="$WORK_DIR/jdk" termux_extract_packages "${PACKAGES[@]}"
)

(
    cd "$WORK_DIR/compiler"
    ZIP="kotlin-compiler-$KOTLIN_VERSION.zip"
    if [ ! -f "$ZIP" ]; then
        curl -L --fail --show-error -o "$ZIP" \
            "https://github.com/JetBrains/kotlin/releases/download/v$KOTLIN_VERSION/$ZIP"
    fi
    printf '%s  %s\n' "$KOTLIN_SHA256" "$ZIP" | sha256sum -c -
    rm -rf kotlinc
    unzip -q "$ZIP"
)

JDK_SRC="$WORK_DIR/jdk/extracted/openjdk-21/data/data/com.termux/files/usr/lib/jvm/java-21-openjdk"
KOTLIN_SRC="$WORK_DIR/compiler/kotlinc"
BASH_SRC="$ROOT_DIR/android/app/src/main/jniLibs/arm64-v8a/libbash.so"
SPAWN_SRC="$ROOT_DIR/android/toolchain_java/src/main/assets/usr/lib/libandroid-spawn.so"
SHMEM_SRC="$ROOT_DIR/android/toolchain_java/src/main/assets/usr/lib/libandroid-shmem.so"

[ -d "$JDK_SRC" ] || { echo "OpenJDK 21 não encontrado" >&2; exit 1; }
[ -d "$KOTLIN_SRC" ] || { echo "Kotlin compiler não encontrado" >&2; exit 1; }
[ -f "$BASH_SRC" ] || { echo "Rode download-termux-tools.sh antes de download-kotlin.sh" >&2; exit 1; }
[ -f "$SPAWN_SRC" ] || { echo "Rode download-java.sh antes de download-kotlin.sh" >&2; exit 1; }
[ -f "$SHMEM_SRC" ] || { echo "Rode download-java.sh antes de download-kotlin.sh" >&2; exit 1; }

rm -rf "$PACK_ASSETS/usr"
mkdir -p "$PACK_ASSETS/usr/bin" "$PACK_ASSETS/usr/lib/kotlin/bin" \
    "$PACK_ASSETS/usr/lib/jvm" "$PACK_ASSETS/usr/lib" "$PACK_ASSETS/usr/share/doc/kotlin"
cp -RL "$JDK_SRC/." "$PACK_ASSETS/usr/lib/jvm/java-21-openjdk/"
cp -RL "$KOTLIN_SRC/lib/." "$PACK_ASSETS/usr/lib/kotlin/"
cp "$KOTLIN_SRC/bin/kotlinc" "$PACK_ASSETS/usr/lib/kotlin/bin/kotlinc"
cp "$BASH_SRC" "$PACK_ASSETS/usr/bin/bash"
cp "$SPAWN_SRC" "$PACK_ASSETS/usr/lib/libandroid-spawn.so"
cp "$SHMEM_SRC" "$PACK_ASSETS/usr/lib/libandroid-shmem.so"
cp "$KOTLIN_SRC/license/LICENSE.txt" "$PACK_ASSETS/usr/share/doc/kotlin/LICENSE.txt"
WORK_DIR="$WORK_DIR/jdk" termux_copy_notices "$PACK_ASSETS/usr" "${PACKAGES[@]}"

python3 "$SCRIPT_DIR/verify-android-elf.py" "$PACK_ASSETS/usr/bin/bash" \
    --lib-dir "$ROOT_DIR/android/app/src/main/assets/usr/lib"
python3 "$SCRIPT_DIR/verify-android-elf.py" \
    "$PACK_ASSETS/usr/lib/jvm/java-21-openjdk/bin/java" \
    --lib-dir "$PACK_ASSETS/usr/lib" \
    --lib-dir "$PACK_ASSETS/usr/lib/jvm/java-21-openjdk/lib" \
    --lib-dir "$ROOT_DIR/android/app/src/main/assets/usr/lib"
python3 "$SCRIPT_DIR/verify-android-elf.py" "$PACK_ASSETS/usr/lib/libandroid-spawn.so" \
    --lib-dir "$ROOT_DIR/android/app/src/main/assets/usr/lib"

BINARIES='["usr/bin/bash"'
while IFS= read -r binary; do
    [ -n "$binary" ] || continue
    BINARIES+=",\"usr/lib/jvm/java-21-openjdk/bin/$binary\""
done < <(for file in "$PACK_ASSETS/usr/lib/jvm/java-21-openjdk/bin"/*; do
    [ -f "$file" ] || continue
    is_elf=false
    [ "$(dd if="$file" bs=4 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n')" = "7f454c46" ] && is_elf=true
    [ "$is_elf" = true ] && basename "$file"
done)
for name in jspawnhelper jexec; do
    file="$PACK_ASSETS/usr/lib/jvm/java-21-openjdk/lib/$name"
    [ -f "$file" ] || continue
    [ "$(dd if="$file" bs=4 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n')" = "7f454c46" ] || continue
    BINARIES+=",\"usr/lib/jvm/java-21-openjdk/lib/$name\""
done
BINARIES+=']'

cat > "$PACK_ASSETS/toolchain_kotlin.json" << EOF
{
    "name": "kotlin",
    "displayName": "Kotlin",
    "version": "$KOTLIN_VERSION",
    "binaries": $BINARIES,
    "env": {
        "JAVACMD": "java",
        "KOTLIN_HOME": "\$FILESDIR/usr/lib/kotlin"
    },
    "pathDirs": ["usr/lib/jvm/java-21-openjdk/bin"],
    "installRoot": "usr/lib/kotlin",
    "libs": ["libandroid-shmem.so", "libandroid-spawn.so"],
    "scriptWrappers": {
        "interpreter": "bash",
        "scripts": {
            "kotlin": "usr/lib/kotlin/bin/kotlinc",
            "kotlinc": "usr/lib/kotlin/bin/kotlinc",
            "kotlinc-jvm": "usr/lib/kotlin/bin/kotlinc"
        }
    }
}
EOF

echo "Kotlin $KOTLIN_VERSION com OpenJDK 21: $(du -sh "$PACK_ASSETS/usr" | cut -f1)"
