// vendor-src/entry.js — the source for web/milkdown.js.
//
// Bundles Milkdown's Crepe editor (markdown in, markdown out) for
// postwisp's editor page. Built by scripts/build-editor.sh with esbuild
// as an IIFE that exposes window.pwMilkdown.
//
// The surface postwisp uses, deliberately small:
//   pwMilkdown.create(root, { defaultValue, placeholder, onChange, onUpload, toolbar })
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
// dependencies — no CodeMirror, no tables, no LaTeX, no AI. The
// selection toolbar (bold/italic/strikethrough, inline code, link, plus
// heading 1/2/3 added below), block editor, cursor hints, link tooltip,
// list item hints, placeholder and image block stay; the top bar
// (heading levels, bold/italic/strike, code, links, lists, quotes, hr)
// only when the caller passes `toolbar: true`.

import { Crepe } from '@milkdown/crepe'
import { insert, replaceAll } from '@milkdown/utils'
import { commandsCtx, editorViewCtx } from '@milkdown/kit/core'
import { headingSchema, setBlockTypeCommand } from '@milkdown/kit/preset/commonmark'

// Heading buttons for the selection toolbar: an H plus the digit, drawn
// as plain strokes so DOMPurify's SVG allowlist passes them untouched.
const hStrokes = '<path d="M4 5v14M4 12h6M10 5v14"/>'
const digit = (level) => {
  if (level === 1) return '<path d="M14.5 6.8 17 5v14"/>'
  if (level === 2) return '<path d="M14.5 6.3c0-1.3 1.1-2.3 2.6-2.3 1.6 0 2.7 1 2.7 2.4 0 3-5.4 5.1-5.4 8.6h5.5"/>'
  return '<path d="M14.6 5.9c.5-1.2 1.4-1.9 2.7-1.9 1.5 0 2.6.9 2.6 2.1 0 1.2-1.1 1.9-2.6 2.2 1.5.3 2.6 1 2.6 2.3 0 1.3-1.1 2.2-2.6 2.2-1.3 0-2.2-.7-2.7-1.9"/>'
}
const headingIcon = (level) => `
  <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"
       fill="none" stroke="currentColor" stroke-width="1.7"
       stroke-linecap="round" stroke-linejoin="round">${hStrokes}${digit(level)}</svg>`

// Turn the block the caret sits in into a heading of the given level —
// the same move the top bar's heading selector makes, reachable from
// the context menu without moving the mouse to the top of the card.
const headingItem = (level) => ({
  icon: headingIcon(level),
  label: 'Heading ' + level,
  active: (ctx) => {
    const view = ctx.get(editorViewCtx)
    const node = view.state.selection.$from.parent
    return node.type === headingSchema.type(ctx) && node.attrs.level === level
  },
  onRun: (ctx) => {
    const commands = ctx.get(commandsCtx)
    commands.call(setBlockTypeCommand.key, {
      nodeType: headingSchema.type(ctx),
      attrs: { level },
    })
  },
})

// Crepe's top-bar buttons carry no labels of their own (icons only), so
// label them for tooltips and screen readers once the bar exists. The
// order is fixed by the feature set enabled below.
const TOP_BAR_LABELS = [
  'Bold', 'Italic', 'Strikethrough', 'Inline code',
  'Bullet list', 'Numbered list', 'Task list',
  'Link', 'Image', 'Code block', 'Blockquote', 'Divider',
]
function labelTopBar(root) {
  if (!root || !root.querySelectorAll) return
  const items = root.querySelectorAll('.milkdown-top-bar .top-bar-item')
  items.forEach((btn, i) => {
    const label = TOP_BAR_LABELS[i]
    if (!label) return
    btn.setAttribute('title', label)
    btn.setAttribute('aria-label', label)
  })
  const selector = root.querySelector('.milkdown-top-bar .top-bar-heading-button')
  if (selector) {
    selector.setAttribute('title', 'Paragraph or heading level')
    selector.setAttribute('aria-label', 'Paragraph or heading level')
  }
}

async function create(root, opts) {
  opts = opts || {}
  const features = {
    [Crepe.Feature.CodeMirror]: false,
    [Crepe.Feature.Table]: false,
    [Crepe.Feature.Latex]: false,
    [Crepe.Feature.AI]: false,
  }
  const featureConfigs = {
    [Crepe.Feature.Placeholder]: {
      text: opts.placeholder || 'Write your post in markdown\u2026',
      mode: 'doc',
    },
    [Crepe.Feature.ImageBlock]: {
      onUpload: opts.onUpload,
      inlineOnUpload: opts.onUpload,
    },
    // The context menu over a selection: Crepe's own marks (bold,
    // italic, strikethrough, inline code, link) plus heading 1/2/3.
    [Crepe.Feature.Toolbar]: {
      buildToolbar: (gb) => {
        const headings = gb.addGroup('headings', 'Headings')
        headings.addItem('h1', headingItem(1))
        headings.addItem('h2', headingItem(2))
        headings.addItem('h3', headingItem(3))
      },
    },
  }
  if (opts.toolbar) {
    // 'shown' keeps the bar on screen instead of fading in on focus
    // (the feature itself is opt-in: Crepe ships it disabled by default,
    // so the feature map must turn it on — a config alone does not)
    features[Crepe.Feature.TopBar] = true
    featureConfigs[Crepe.Feature.TopBar] = {
      displayMode: 'shown',
      // paragraphs and the three heading levels a blog post needs
      headingOptions: [
        { label: 'Paragraph', level: null },
        { label: 'Heading 1', level: 1 },
        { label: 'Heading 2', level: 2 },
        { label: 'Heading 3', level: 3 },
      ],
    }
  } else {
    features[Crepe.Feature.TopBar] = false
  }
  const crepe = new Crepe({
    root: root,
    defaultValue: opts.defaultValue || '',
    features: features,
    featureConfigs: featureConfigs,
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
  if (opts.toolbar) labelTopBar(root)
  return {
    getMarkdown: () => crepe.getMarkdown(),
    insert: (markdown) => crepe.editor.action(insert(markdown)),
    setMarkdown: (markdown) => crepe.editor.action(replaceAll(markdown)),
    focus: () => { try { crepe.editor.view.focus() } catch (e) { /* already gone */ } },
    destroy: () => crepe.destroy(),
  }
}

export { create }
