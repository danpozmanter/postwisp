#!/usr/bin/env bash
# scripts/build-editor.sh — rebuild web/milkdown.js and web/milkdown.css
# from the npm sources pinned in vendor-src/ (Milkdown / Crepe).
#
# The built artifacts are committed under web/ and served by the binary,
# so a deployment never needs node: this script is only run when the
# editor bundle is changed (and by CI, if ever wanted).
set -euo pipefail
cd "$(dirname "$0")/../vendor-src"

[ -f entry.js ] || { echo "vendor-src/entry.js is missing" >&2; exit 1; }
[ -d node_modules ] || npm install --no-audit --no-fund

npx esbuild entry.js --bundle --minify --format=iife \
  --global-name=pwMilkdown --charset=utf8 --outfile=../web/milkdown.js

# Crepe's component styles for exactly the features postwisp enables
# (see entry.js), plus the postwisp theme bridge.
{
  for part in prosemirror reset block-edit cursor image-block \
              link-tooltip list-item placeholder toolbar; do
    cat "node_modules/@milkdown/crepe/lib/theme/common/${part}.css"
    echo
  done
  cat ../scripts/milkdown-theme.css
} > ../web/milkdown.css

echo "built web/milkdown.js ($(wc -c < ../web/milkdown.js) bytes)"
echo "built web/milkdown.css ($(wc -c < ../web/milkdown.css) bytes)"
