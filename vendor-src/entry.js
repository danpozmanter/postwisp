// vendor-src/entry.js — the source for web/milkdown.js.
//
// Bundles Milkdown's Crepe editor (markdown in, markdown out) for
// postwisp's two editors. Built by scripts/build-editor.sh with esbuild
// as an IIFE that exposes window.pwMilkdown.
//
// The surface postwisp uses, deliberately small:
//   pwMilkdown.create(root, { defaultValue, placeholder, onChange, onUpload })
//     -> { getMarkdown, insert, setMarkdown, focus, destroy }
//
// - onChange fires on every markdown change (the page debounces preview).
// - onUpload(file) -> Promise<url> is what the image block calls when a
//   picture is dropped or pasted in; the page routes it to /api/media.
// - insert(markdown) splices parsed markdown at the cursor — used by the
//   Unsplash picker and the upload button.
// - setMarkdown replaces the whole document (loading a post, swapping the
//   cover image).
//
// Features: everything Crepe ships except the ones that pull heavy
// dependencies or duplicate postwisp's own chrome — no CodeMirror, no
// tables, no LaTeX, no AI, no top bar. The toolbar, block editor, cursor
// hints, link tooltip, list item hints, placeholder and image block stay.

import { Crepe } from '@milkdown/crepe'
import { insert, replaceAll } from '@milkdown/utils'

async function create(root, opts) {
  opts = opts || {}
  const crepe = new Crepe({
    root: root,
    defaultValue: opts.defaultValue || '',
    features: {
      [Crepe.Feature.CodeMirror]: false,
      [Crepe.Feature.Table]: false,
      [Crepe.Feature.Latex]: false,
      [Crepe.Feature.AI]: false,
      [Crepe.Feature.TopBar]: false,
    },
    featureConfigs: {
      [Crepe.Feature.Placeholder]: {
        text: opts.placeholder || 'Write your post in markdown\u2026',
        mode: 'doc',
      },
      [Crepe.Feature.ImageBlock]: {
        onUpload: opts.onUpload,
        inlineOnUpload: opts.onUpload,
      },
    },
  })
  if (opts.onChange) {
    // registered before create() so the listener is live from the first
    // keystroke, not just after the first re-render
    crepe.on((api) => {
      api.markdownUpdated((_ctx, markdown, prev) => {
        if (markdown !== prev) opts.onChange(markdown)
      })
    })
  }
  await crepe.create()
  return {
    getMarkdown: () => crepe.getMarkdown(),
    insert: (markdown) => crepe.editor.action(insert(markdown)),
    setMarkdown: (markdown) => crepe.editor.action(replaceAll(markdown)),
    focus: () => { try { crepe.editor.view.focus() } catch (e) { /* already gone */ } },
    destroy: () => crepe.destroy(),
  }
}

export { create }
