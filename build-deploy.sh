#!/usr/bin/env bash
# build-deploy.sh — cross-build postwisp for a deployment target and
# assemble a deployable directory (dist/ by default).
#
# For a build that runs on THIS machine, use build-local.sh instead.
#
# Usage: ./build-deploy.sh [TARGET] [--dir=DIR]
#   TARGET      one of: linux-x64 (default), linux-arm64, macos-arm64,
#               macos-x64, win-x64
#   --dir=DIR   build into DIR instead of dist/ (also: --dir DIR)
#   --help      show this help
set -euo pipefail
cd "$(dirname "$0")"

usage() {
    cat <<'HELP'
build-deploy.sh — cross-build postwisp for a deployment target.

Usage: ./build-deploy.sh [TARGET] [--dir=DIR]

Targets:
  linux-x64     x86_64 Linux, static musl (default; the typical server)
  linux-arm64   aarch64 Linux, static musl (ARM servers, Raspberry Pi)
  macos-arm64   Apple Silicon macOS — requires building ON a Mac
  macos-x64     Intel macOS — requires building ON a Mac
  win-x64       Windows x86_64 — requires building ON Windows

The script sets up cross-build prerequisites itself (rustup target,
the gossamer runtime archive from the pinned toolchain release).

Options:
  --dir=DIR     build into DIR instead of dist/ (also: --dir DIR)
  --help        show this help

The target directory is emptied first if it has anything in it, then
filled with everything you run postwisp from: the binary, templates/,
web/, scripts/setup.sh, and README-env.md.
HELP
}

TARGET="linux-x64"
DIR="dist"
TARGET_SET=0
while [ $# -gt 0 ]; do
    case "$1" in
        --dir=*) DIR="${1#--dir=}" ;;
        --dir)   [ $# -ge 2 ] || { echo "error: --dir needs a value" >&2; exit 1; }
                 DIR="$2"; shift ;;
        --help|-h) usage; exit 0 ;;
        -*|*) if [ "$1" = "linux-x64" ] || [ "$1" = "linux-arm64" ] ||
                 [ "$1" = "macos-arm64" ] || [ "$1" = "macos-x64" ] ||
                 [ "$1" = "win-x64" ]; then
                  if [ "$TARGET_SET" = 1 ]; then
                      echo "error: TARGET given twice ('$TARGET' and '$1')" >&2; exit 1
                  fi
                  TARGET="$1"; TARGET_SET=1
              else
                  echo "error: unknown target or argument: $1" >&2
                  echo "valid targets: linux-x64 linux-arm64 macos-arm64 macos-x64 win-x64" >&2
                  exit 1
              fi ;;
    esac
    shift
done

case "$TARGET" in
    linux-x64)   TRIPLE="x86_64-unknown-linux-musl" ;;
    linux-arm64) TRIPLE="aarch64-unknown-linux-musl" ;;
    macos-arm64) TRIPLE="aarch64-apple-darwin" ;;
    macos-x64)   TRIPLE="x86_64-apple-darwin" ;;
    win-x64)     TRIPLE="x86_64-pc-windows-msvc" ;;
esac

# --- cross-build prerequisites -------------------------------------------
# The gossamer toolchain needs, per target: a rustup target (the musl
# cross link drives the rustup linker component), and — where the local
# toolchain install does not ship it — the runtime archive from the same
# pinned gossamer release (keep in step with `gossamer-version` in
# project.toml).
GOSSAMER_VERSION="$(awk -F'"' '
    /^\[project\]$/ { in_section = 1; next }
    /^\[/ { in_section = 0 }
    in_section && $1 ~ /^gossamer-version = / { print $2; exit }
' project.toml)"
[ -n "$GOSSAMER_VERSION" ] || { echo "error: could not read gossamer-version from project.toml" >&2; exit 1; }
VER_NUM="${GOSSAMER_VERSION#^}"
VER_NUM="${VER_NUM#v}"

case "$TRIPLE" in
    *-linux-musl)
        command -v rustup >/dev/null 2>&1 || {
            echo "error: rustup not found — it provides the cross linker for $TRIPLE" >&2
            exit 1
        }
        rustup target add "${TRIPLE}" >&2
        ARCH="${TRIPLE%%-*}"   # x86_64 or aarch64
        # Env var the toolchain reads: the triple with '-' as '_',
        # uppercased (GOS_RUNTIME_LIB_AARCH64_UNKNOWN_LINUX_MUSL).
        ENV_VAR="GOS_RUNTIME_LIB_${TRIPLE//-/_}"
        ENV_VAR="${ENV_VAR^^}"
        if [ -z "${!ENV_VAR:-}" ] && [ "$ARCH" != "$(uname -m)" ]; then
            # The runtime archive must ABI-match the gos compiler doing
            # the link. Try the installed toolchain's own release first;
            # if none is published for it, fall back to the release
            # workflow's known-good pin.
            TOOLCHAIN_VER="$(gos --version | awk '{print $2}')"
            VERSIONS="v${TOOLCHAIN_VER} v0.64.0 v0.61.1"
            TMP="$(mktemp -d)"
            trap 'rm -rf "$TMP"' EXIT
            for V in $VERSIONS; do
                VER_NUM="${V#v}"
                echo "Fetching the gossamer $ARCH runtime archive ($V)..." >&2
                if curl -fsSL -o "$TMP/gos-$ARCH.tar.gz" \
                    "https://github.com/gossamer-lang/gossamer/releases/download/${V}/gos-${VER_NUM}-linux-${ARCH}.tar.gz"; then
                    tar -xzf "$TMP/gos-$ARCH.tar.gz" -C "$TMP"
                    RUNTIME_LIB="$(find "$TMP" -path '*/gos-*/libgossamer_runtime-musl.a' | head -n1)"
                    [ -n "$RUNTIME_LIB" ] && break
                fi
                echo "  ...no archive for $V; trying the next known-good release" >&2
                rm -rf "$TMP"; TMP="$(mktemp -d)"
            done
            [ -n "${RUNTIME_LIB:-}" ] || {
                echo "error: no matching libgossamer_runtime-musl.a release found (tried: $VERSIONS)" >&2
                exit 1
            }
            export "$ENV_VAR=$(cd "$(dirname "$RUNTIME_LIB")" && pwd)/$(basename "$RUNTIME_LIB")"
        fi
        ;;
esac

gos build --release --target "$TRIPLE"

# project.toml's `output` (target/debug/postwisp) governs where the
# toolchain links the binary, --target included. Windows links it as
# postwisp.exe instead — pick whichever exists.
BIN_OUT="target/debug/postwisp"
[ -f "$BIN_OUT" ] || BIN_OUT="target/debug/postwisp.exe"

if [ -d "$DIR" ] && [ -n "$(ls -A "$DIR" 2>/dev/null)" ]; then
    echo "Cleaning $DIR ..."
    rm -rf "$DIR"
fi
mkdir -p "$DIR/scripts"
cp "$BIN_OUT" "$DIR/postwisp"
cp -r templates "$DIR/templates"
cp -r web "$DIR/web"
cp scripts/setup.sh "$DIR/scripts/setup.sh"
cp scripts/README-env.md "$DIR/README-env.md"

echo
echo "$DIR/ is ready (target: $TARGET / $TRIPLE):"
ls -R "$DIR"
echo
echo "Next: copy the CONTENTS of $DIR/ to your server, then run"
echo "  ./scripts/setup.sh"
echo "from that directory."
