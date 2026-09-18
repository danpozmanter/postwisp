#!/bin/sh
# Postwisp installer for macOS.
#
# Two modes:
#   --user    install into ~/.local (no sudo needed; default)
#   --system  install into /usr/local (may prompt for sudo)
#
# The script works both as a local installer (run from a release
# archive after extracting it — it sits next to `postwisp`,
# `templates/`, `web/`, and `scripts/`) and as a remote bootstrap:
#
#     curl -fsSL https://raw.githubusercontent.com/danpozmanter/postwisp/main/scripts/install.sh | sh
#     curl -fsSL https://raw.githubusercontent.com/danpozmanter/postwisp/main/scripts/install.sh | sh -s -- --system
#
# Honoured environment variables:
#   POSTWISP_VERSION  release tag to install (default: "latest")
#   POSTWISP_REPO     github owner/repo     (default: "danpozmanter/postwisp")
#   POSTWISP_PREFIX   install root          (overrides --user / --system)

set -eu

REPO="${POSTWISP_REPO:-danpozmanter/postwisp}"
VERSION="${POSTWISP_VERSION:-latest}"

MODE="user"
for arg in "$@"; do
    case "$arg" in
        --user)    MODE="user" ;;
        --system)  MODE="system" ;;
        -h|--help)
            sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "postwisp-install: unknown argument: $arg" >&2
            exit 2
            ;;
    esac
done

if [ -n "${POSTWISP_PREFIX:-}" ]; then
    PREFIX="$POSTWISP_PREFIX"
elif [ "$MODE" = "system" ]; then
    PREFIX="/usr/local"
else
    PREFIX="$HOME/.local"
fi
BIN_DIR="$PREFIX/bin"
SHARE_DIR="$PREFIX/share/postwisp"

uname_s=$(uname -s 2>/dev/null || echo unknown)
uname_m=$(uname -m 2>/dev/null || echo unknown)

# postwisp releases macOS archives only; Linux and Windows users should
# grab the matching release archive and deploy it directly.
case "$uname_s" in
    Darwin) os="macos" ;;
    Linux)
        echo "postwisp-install: this installer is for macOS only." >&2
        echo "                  On Linux, download postwisp-<version>-linux-<arch>.tar.gz" >&2
        echo "                  from https://github.com/$REPO/releases and deploy the" >&2
        echo "                  extracted directory (see the README)." >&2
        exit 1
        ;;
    *)
        echo "postwisp-install: unsupported host OS: $uname_s" >&2
        echo "                  On Windows, download postwisp-<version>-windows-x86_64.zip" >&2
        echo "                  from https://github.com/$REPO/releases." >&2
        exit 1
        ;;
esac

case "$uname_m" in
    x86_64|amd64)      arch="x86_64" ;;
    arm64|aarch64)     arch="aarch64" ;;
    *)
        echo "postwisp-install: unsupported host architecture: $uname_m" >&2
        exit 1
        ;;
esac

ensure_dir() {
    dir="$1"
    if [ -d "$dir" ]; then
        return
    fi
    # Find the deepest existing ancestor and see if we can write there.
    probe="$dir"
    while [ ! -d "$probe" ]; do
        probe="$(dirname "$probe")"
    done
    if [ -w "$probe" ]; then
        mkdir -p "$dir"
    elif command -v sudo >/dev/null 2>&1; then
        sudo mkdir -p "$dir"
    else
        echo "postwisp-install: cannot create $dir and sudo not available" >&2
        exit 1
    fi
}

# Copy a file into the install root, staging and renaming so existing
# processes keep their old inode while new invocations see the complete
# new file atomically (and to avoid ETXTBSY on a running binary).
install_file() {
    src="$1"
    dest="$2"
    mode="$3"
    if [ -w "$(dirname "$dest")" ]; then
        staged="${dest}.install.$$"
        trap 'rm -f "$staged"' EXIT HUP INT TERM
        cp "$src" "$staged"
        chmod "$mode" "$staged"
        mv -f "$staged" "$dest"
        trap - EXIT HUP INT TERM
    elif command -v sudo >/dev/null 2>&1; then
        staged="${dest}.install.$$"
        sudo cp "$src" "$staged"
        sudo chmod "$mode" "$staged"
        sudo mv -f "$staged" "$dest"
    else
        echo "postwisp-install: cannot write to $dest and sudo not available" >&2
        exit 1
    fi
    # macOS Gatekeeper quarantines binaries unzipped from a browser
    # download (com.apple.quarantine xattr). CI ad-hoc-codesigns the
    # binary, but Gatekeeper still blocks until the attribute is
    # removed. Strip it best-effort; harmless when absent.
    if command -v xattr >/dev/null 2>&1; then
        if [ -w "$dest" ]; then
            xattr -d com.apple.quarantine "$dest" 2>/dev/null || true
        elif command -v sudo >/dev/null 2>&1; then
            sudo xattr -d com.apple.quarantine "$dest" 2>/dev/null || true
        fi
    fi
}

link_bin() {
    # Symlink the launcher last, so a partially-installed tree never
    # advertises a `postwisp` command.
    target="$1"
    link="$BIN_DIR/postwisp"
    ensure_dir "$BIN_DIR"
    if [ -w "$BIN_DIR" ]; then
        ln -sfn "$target" "$link"
    elif command -v sudo >/dev/null 2>&1; then
        sudo ln -sfn "$target" "$link"
    else
        echo "postwisp-install: cannot write to $link and sudo not available" >&2
        exit 1
    fi
}

# Installs the payload sitting in directory $1 (binary at $1/postwisp,
# templates/, web/, scripts/ beside it) into $SHARE_DIR, then links the
# launcher.
install_payload() {
    src_dir="$1"
    ensure_dir "$SHARE_DIR"
    install_file "$src_dir/postwisp" "$SHARE_DIR/postwisp" 755
    rm -rf "$SHARE_DIR/templates" "$SHARE_DIR/web" "$SHARE_DIR/scripts"
    if [ -w "$SHARE_DIR" ]; then
        cp -R "$src_dir/templates" "$src_dir/web" "$src_dir/scripts" "$SHARE_DIR/"
        cp "$src_dir/README-env.md" "$SHARE_DIR/README-env.md" 2>/dev/null || true
    else
        sudo cp -R "$src_dir/templates" "$src_dir/web" "$src_dir/scripts" "$SHARE_DIR/"
        sudo cp "$src_dir/README-env.md" "$SHARE_DIR/README-env.md" 2>/dev/null || true
    fi
    link_bin "$SHARE_DIR/postwisp"
}

# Path 1 - local install from an already-extracted archive.
script_dir="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
if [ -f "$script_dir/postwisp" ]; then
    install_payload "$script_dir"
    printf 'Installed postwisp to %s\n' "$SHARE_DIR"
    case ":$PATH:" in
        *":$BIN_DIR:"*) ;;
        *)
            printf '\nNote: %s is not on your PATH.\n' "$BIN_DIR"
            printf 'Add the following line to your shell profile to use `postwisp`:\n'
            printf '    export PATH="%s:$PATH"\n' "$BIN_DIR"
            ;;
    esac
    printf '\nNext steps:\n'
    printf '  cd %s        # the site lives here (data/, templates/, web/)\n' "$SHARE_DIR"
    printf '  ./scripts/setup.sh       # first-run walkthrough (bind address, service)\n'
    printf 'Or run `postwisp` from any directory and set PW_TEMPLATES / PW_WEB\n'
    printf 'to the templates/ and web/ directories here.\n'
    exit 0
fi

# Path 2 - remote bootstrap: download the release asset.
if ! command -v curl >/dev/null 2>&1; then
    echo "postwisp-install: curl is required for remote installs" >&2
    exit 1
fi
if ! command -v unzip >/dev/null 2>&1; then
    echo "postwisp-install: unzip is required for remote installs" >&2
    echo "                  (macOS ships it; install Xcode command line tools: xcode-select --install)" >&2
    exit 1
fi

if [ "$VERSION" = "latest" ]; then
    VERSION_URL="https://api.github.com/repos/$REPO/releases/latest"
    TAG=$(curl -fsSL "$VERSION_URL" | sed -n 's/^[[:space:]]*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)
    if [ -z "$TAG" ]; then
        echo "postwisp-install: could not read latest release tag from $VERSION_URL" >&2
        exit 1
    fi
else
    TAG="$VERSION"
fi

# Strip leading `v` on the tag for filename matching.
VER_NUM=$(printf '%s' "$TAG" | sed 's/^v//')

ASSET="postwisp-${VER_NUM}-macos-${arch}.zip"
URL="https://github.com/$REPO/releases/download/$TAG/$ASSET"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

printf 'Downloading %s ...\n' "$URL"
curl -fL -o "$tmp/$ASSET" "$URL"

cd "$tmp"
unzip -q "$ASSET"

extracted_dir="$(find . -maxdepth 1 -mindepth 1 -type d | head -n1)"
if [ -z "$extracted_dir" ] || [ ! -f "$extracted_dir/postwisp" ]; then
    echo "postwisp-install: extracted archive layout unexpected" >&2
    exit 1
fi

install_payload "$extracted_dir"

printf 'Installed postwisp %s to %s\n' "$TAG" "$SHARE_DIR"
case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *)
        printf '\nNote: %s is not on your PATH.\n' "$BIN_DIR"
        printf 'Add the following line to your shell profile to use `postwisp`:\n'
        printf '    export PATH="%s:$PATH"\n' "$BIN_DIR"
        ;;
esac
printf '\nNext steps:\n'
printf '  cd %s        # the site lives here (data/, templates/, web/)\n' "$SHARE_DIR"
printf '  ./scripts/setup.sh       # first-run walkthrough (bind address, service)\n'
