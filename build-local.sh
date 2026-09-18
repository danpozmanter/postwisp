#!/usr/bin/env bash
# build-local.sh — build postwisp for THIS machine and assemble a
# deployable directory (dist/ by default).
#
# For a build that targets a server (different OS/architecture), use
# build-deploy.sh instead.
#
# Usage: ./build-local.sh [--dir=DIR]
#   --dir=DIR   build into DIR instead of dist/ (also: --dir DIR)
#   --help      show this help
#
# The target directory is emptied first if it has anything in it, then
# filled with everything you run postwisp from:
#   postwisp          the release binary
#   templates/        index.html post.html list.html about.html (inline CSS)
#   web/              built-in admin/editor/setup pages the binary serves
#   scripts/setup.sh  first-run walkthrough (run it ON THE SERVER)
#   README-env.md     environment variables the server reads at boot
set -euo pipefail
cd "$(dirname "$0")"

usage() {
    sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
}

DIR="dist"
while [ $# -gt 0 ]; do
    case "$1" in
        --dir=*) DIR="${1#--dir=}" ;;
        --dir)   [ $# -ge 2 ] || { echo "error: --dir needs a value" >&2; exit 1; }
                 DIR="$2"; shift ;;
        --help|-h) usage; exit 0 ;;
        *) echo "error: unknown argument: $1 (try --help)" >&2; exit 1 ;;
    esac
    shift
done

gos build --release

# project.toml's `output` (target/debug/postwisp) governs where the
# toolchain links the binary, release included. On Windows it may land
# as postwisp.exe instead — pick whichever exists.
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
echo "$DIR/ is ready:"
ls -R "$DIR"
echo
echo "Next: to deploy, copy the CONTENTS of $DIR/ to your server, then run"
echo "  ./scripts/setup.sh"
echo "from that directory."
