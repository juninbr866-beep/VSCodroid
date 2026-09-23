#!/usr/bin/env bash
set -euo pipefail

# VSCodroid simple package installer
# Downloads .deb packages from Termux repo and extracts to $PREFIX
# No apt/dpkg database - just extracts files

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
PREFIX="${PREFIX:-/data/data/com.vscodroid/files/usr}"
WORK_DIR="${WORK_DIR:-$ROOT_DIR/.build/vscodroid-install}"
TERMUX_REPO="${TERMUX_MIRROR:-https://mirror.mwt.me/termux/main}"
PACKAGES_URL="$TERMUX_REPO/dists/stable/main/binary-aarch64/Packages"

usage() {
    cat <<'EOF'
Usage: vscodroid-install [options] <command> [packages...]

Commands:
  install <packages...>   Install packages
  search <query>          Search packages by name/description
  show <packages...>      Show package info
  list                    List all available packages
  update                  Update package index

Options:
  --prefix DIR            Install prefix (default: $PREFIX)
  --dry-run               Show what would be done
  -y, --yes               Assume yes to prompts
  -h, --help              Show this help

Examples:
  vscodroid-install install vim htop
  vscodroid-install search python
  vscodroid-install show neovim
EOF
}

log() { echo "[$(date '+%H:%M:%S')] $*" >&2; }
err() { echo "[$(date '+%H:%M:%S')] ERROR: $*" >&2; }
die() { err "$*"; exit 1; }

require_work_dir() {
    mkdir -p "$WORK_DIR"
}

fetch_index() {
    require_work_dir
    local index="$WORK_DIR/Packages"
    
    if [ ! -f "$index" ] || [ -n "$(find "$index" -mmin +60 2>/dev/null)" ]; then
        log "Downloading package index..."
        curl -L --fail --show-error -o "$index" "$PACKAGES_URL"
        log "  Downloaded: $(du -sh "$index" | cut -f1)"
    else
        log "Using cached index (< 1 hour old)"
    fi
}

resolve_package() {
    local pkg="$1"
    local pkg_line
    pkg_line=$(awk -v pkg="$pkg" '
        /^Package: / { 
            if (fn != "" && current == pkg) exit
            current = $2
            fn = ""
            sh = ""
            ver = ""
            desc = ""
            dep = ""
        }
        /^Filename: / && current == pkg { fn = $2 }
        /^SHA256: / && current == pkg { sh = $2 }
        /^Version: / && current == pkg { ver = $2 }
        /^Description: / && current == pkg { desc = substr($0, 14); gsub(/"/, "", desc) }
        /^Depends: / && current == pkg { dep = substr($0, 10); gsub(/, /, " ", dep) }
        END { if (fn != "") print fn "|" (sh == "" ? "-" : sh) "|" ver "|" desc "|" dep }
    ' "$WORK_DIR/Packages")
    
    if [ -z "$pkg_line" ]; then
        return 1
    fi
    
    echo "$pkg_line"
}

download_deb() {
    local filename="$1"
    local expected_sha="$2"
    local debname="$(basename "$filename")"
    local debpath="$WORK_DIR/debs/$debname"
    
    mkdir -p "$WORK_DIR/debs"
    
    if [ -f "$debpath" ]; then
        log "  $debname (cached)"
    else
        log "  Downloading $debname..."
        curl -L --fail --show-error -o "$debpath" "$TERMUX_REPO/$filename"
    fi
    
    if [ "$expected_sha" != "-" ] && [ -n "$expected_sha" ]; then
        local actual
        actual=$(sha256sum "$debpath" | cut -d' ' -f1)
        if [ "$actual" != "$expected_sha" ]; then
            err "  SHA256 mismatch for $debname"
            err "    expected: $expected_sha"
            err "    actual:   $actual"
            rm -f "$debpath"
            return 1
        fi
    fi
    
    echo "$debpath"
}

extract_deb() {
    local debpath="$1"
    local destdir="$2"
    local pkgname="$(basename "$debpath" .deb)"
    local extract_dir="$WORK_DIR/extracted/$pkgname"
    
    rm -rf "$extract_dir"
    mkdir -p "$extract_dir"
    
    (
        cd "$extract_dir"
        # .deb is an ar archive; use ar to extract
        ar x "$debpath" || die "ar x failed on $debpath"
        if [ -f data.tar.xz ]; then
            tar xf data.tar.xz
        elif [ -f data.tar.gz ]; then
            tar xf data.tar.gz
        elif [ -f data.tar.zst ]; then
            zstd -d data.tar.zst -o data.tar && tar xf data.tar
        else
            die "Could not extract data archive from $debpath"
        fi
    )
    
    # Copy to prefix, preserving structure
    local datadir="$extract_dir/data/data/com.termux/files/usr"
    if [ ! -d "$datadir" ]; then
        die "Expected Termux prefix structure not found in $debpath"
    fi
    
    mkdir -p "$destdir"
    cp -a "$datadir/." "$destdir/"
    log "  Extracted to $destdir"
}

install_package() {
    local pkg="$1"
    local dry_run="${2:-false}"
    local assume_yes="${3:-false}"
    local auto_deps="${4:-true}"
    
    log "Resolving $pkg..."
    local resolved
    resolved=$(resolve_package "$pkg") || die "Package '$pkg' not found in repository"
    
    local filename sha256 version description depends
    filename=$(echo "$resolved" | cut -d'|' -f1)
    sha256=$(echo "$resolved" | cut -d'|' -f2)
    version=$(echo "$resolved" | cut -d'|' -f3)
    description=$(echo "$resolved" | cut -d'|' -f4)
    depends=$(echo "$resolved" | cut -d'|' -f5)
    
    log "  $pkg $version - $description"
    if [ -n "$depends" ] && [ "$depends" != "-" ]; then
        log "  Depends: $depends"
        if [ "$auto_deps" = "true" ]; then
            for dep in $depends; do
                # Skip version constraints like "libfoo (>= 1.0)"
                dep=$(echo "$dep" | sed 's/ ([^)]*)//g')
                if [ -n "$dep" ]; then
                    log "  Auto-installing dependency: $dep"
                    install_package "$dep" "$dry_run" "$assume_yes" false
                fi
            done
        fi
    fi
    
    if [ "$dry_run" = "true" ]; then
        log "  [dry-run] Would download and extract"
        return 0
    fi
    
    if [ "$assume_yes" = "false" ]; then
        read -rp "  Install? [Y/n] " confirm
        case "$confirm" in
            [nN]*) log "  Skipped"; return 0 ;;
        esac
    fi
    
    local debpath
    debpath=$(download_deb "$filename" "$sha256") || return 1
    
    log "  Extracting..."
    extract_deb "$debpath" "$PREFIX"
    
    log "  Installed $pkg"
}

search_packages() {
    local query="$1"
    fetch_index
    
    log "Searching for '$query'..."
    awk -v q="$query" '
        BEGIN { IGNORECASE=1 }
        /^Package: / { pkg = $2; fn = ""; ver = ""; desc = "" }
        /^Version: / && pkg != "" { ver = $2 }
        /^Description: / && pkg != "" { desc = substr($0, 14) }
        /^Filename: / && pkg != "" { fn = $2 }
        /^$/ && pkg != "" {
            if (pkg ~ q || desc ~ q) {
                printf "%-30s %-15s %s\n", pkg, ver, desc
            }
            pkg = ""
        }
    ' "$WORK_DIR/Packages"
}

show_package() {
    local pkg="$1"
    fetch_index
    
    local resolved
    resolved=$(resolve_package "$pkg") || die "Package '$pkg' not found"
    
    local filename sha256 version description depends
    filename=$(echo "$resolved" | cut -d'|' -f1)
    sha256=$(echo "$resolved" | cut -d'|' -f2)
    version=$(echo "$resolved" | cut -d'|' -f3)
    description=$(echo "$resolved" | cut -d'|' -f4)
    depends=$(echo "$resolved" | cut -d'|' -f5)
    
    echo "Package: $pkg"
    echo "Version: $version"
    echo "Filename: $filename"
    echo "SHA256:  $sha256"
    echo "Description: $description"
    [ -n "$depends" ] && [ "$depends" != "-" ] && echo "Depends: $depends"
}

list_packages() {
    fetch_index
    
    awk '
        /^Package: / { pkg = $2; ver = "" }
        /^Version: / && pkg != "" { ver = $2 }
        /^Description: / && pkg != "" { desc = substr($0, 14); gsub(/  +/, " ", desc); print pkg " " ver " " desc; pkg = "" }
    ' "$WORK_DIR/Packages" | column -t
}

update_index() {
    require_work_dir
    rm -f "$WORK_DIR/Packages"
    fetch_index
    log "Index updated"
}

main() {
    local cmd=""
    local packages=()
    local dry_run=false
    local assume_yes=false
    
    # Parse all args - global options can appear anywhere
    while [ $# -gt 0 ]; do
        case "$1" in
            --prefix)
                PREFIX="$2"
                shift 2
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            -y|--yes)
                assume_yes=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            install|search|show|list|update)
                if [ -n "$cmd" ]; then
                    err "Multiple commands specified"
                    exit 1
                fi
                cmd="$1"
                shift
                ;;
            *)
                # Remaining args are packages/queries for the command
                packages+=("$1")
                shift
                ;;
        esac
    done
    
    [ -z "$cmd" ] && { usage; exit 1; }
    
    case "$cmd" in
        install)
            [ ${#packages[@]} -eq 0 ] && { err "No packages specified"; exit 1; }
            fetch_index
            for pkg in "${packages[@]}"; do
                install_package "$pkg" "$dry_run" "$assume_yes"
            done
            ;;
        search)
            [ ${#packages[@]} -eq 0 ] && { err "No search query"; exit 1; }
            search_packages "${packages[0]}"
            ;;
        show)
            [ ${#packages[@]} -eq 0 ] && { err "No package specified"; exit 1; }
            for pkg in "${packages[@]}"; do
                show_package "$pkg"
                echo
            done
            ;;
        list)
            list_packages
            ;;
        update)
            update_index
            ;;
    esac
}

main "$@"