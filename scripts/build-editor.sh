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

# es2018, not esnext: an untargeted build shipped class static blocks and
# ??=, which older engines (Safari < 16.4, Chrome < 94) reject with a
# SyntaxError — the whole file fails to parse, so window.pwMilkdown is
# never assigned and the edit page dies with "pwMilkdown is not defined".
npx esbuild entry.js --bundle --minify --format=iife --target=es2018 \
  --global-name=pwMilkdown --charset=utf8 --outfile=../web/milkdown.js

# Crepe's component styles for exactly the features postwisp enables
# (see entry.js), plus the postwisp theme bridge.
#
# The Crepe parts reference prosemirror's own styles with bundler-only
# package specifiers (`@import '@milkdown/kit/...'`). A browser cannot
# resolve those: served as-is they 404 and ProseMirror's base styles
# never arrive. The three stylesheets are shipped inline instead, and
# every remaining @import line is stripped so nothing dangles.
{
  for dep in prosemirror-view/style/prosemirror.css \
             prosemirror-gapcursor/style/gapcursor.css \
             prosemirror-virtual-cursor/style/virtual-cursor.css; do
    cat "node_modules/$dep"
    echo
  done
  for part in prosemirror reset block-edit cursor image-block \
              link-tooltip list-item placeholder toolbar top-bar; do
    cat "node_modules/@milkdown/crepe/lib/theme/common/${part}.css"
    echo
  done
  cat ../scripts/milkdown-theme.css
} | grep -v '^[[:space:]]*@import' > ../web/milkdown.css

echo "built web/milkdown.js ($(wc -c < ../web/milkdown.js) bytes)"
echo "built web/milkdown.css ($(wc -c < ../web/milkdown.css) bytes)"
