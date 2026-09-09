#!/usr/bin/env bash
# build.sh — build the release binary and assemble the deployable dist/ directory.
#
# dist/ ends up containing everything you copy to your server:
#   postwisp          the release binary
#   templates/        index.html post.html list.html about.html (inline CSS)
#   web/              built-in admin/editor/setup pages the binary serves
#   scripts/setup.sh  first-run walkthrough (run it ON THE SERVER)
set -euo pipefail
cd "$(dirname "$0")"

gos build --release

# project.toml's `output` (target/debug/postwisp) governs where the
# toolchain links the binary, release included.
BIN_OUT="target/debug/postwisp"

rm -rf dist
mkdir -p dist/scripts
cp "$BIN_OUT" dist/postwisp
cp -r templates dist/templates
cp -r web dist/web
cp scripts/setup.sh dist/scripts/setup.sh

echo
echo "dist/ is ready:"
ls -R dist
echo
echo "Next: copy the CONTENTS of dist/ to your server, then run"
echo "  ./scripts/setup.sh"
echo "from that directory."
