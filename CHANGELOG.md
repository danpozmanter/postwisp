# Changelog
## 0.1.0 - Unreleased
- Self-hosted multi-user blog in one binary: server, JSON API, admin dashboard, and public pages, with embedded terndb storage.
- Markdown writing in **one** editor: the write page at `/editor` (the old embedded dashboard editor is gone — "New post", each post's edit link, and the About-page button all navigate there, so there is exactly one place a post can be edited). It is a single full-width writing card with a **heading outline** beside it: the outline column lists every heading in the post (parsed live from the markdown, in both the styled and raw view), highlights the section you are in as you scroll, and clicking an entry jumps there. The formatting toolbar (paragraph/heading levels, bold/italic/strikethrough, inline and block code, links, lists, quotes, divider) is fused into the card's top edge — every button is labelled for tooltips and screen readers — the **selection context menu** carries bold, italic, strikethrough, inline code, and links plus **heading 1/2/3**, and the **Raw markdown** toggle flips between the styled view and the plain source. The writing surface is styled like the published post and fills the viewport, so the whole editing area is on screen at once.
- The editor bundle is built for ES2018: older browsers (Safari < 16.4, Chrome < 94) get a working editor instead of a `SyntaxError` that leaves the page at "pwMilkdown is not defined"; if the bundle ever fails to load anyway, both editors now say so on the page.
- Media uploads (photos, video, audio) with content sniffing from magic bytes, `Range`/`ETag` streaming, and per-author media libraries.
- Cover photos from Unsplash search, stored with the post's markdown.
- Themes as four plain HTML templates with inline CSS, re-read from disk on every request.
- Public pages in English, German, French, and Spanish, with localized dates and a per-visitor language switcher.
- Light/dark theme with a site-wide default and a per-visitor toggle, applied pre-paint, with reduced-motion support.
- Accounts: no open registration, admin-created authors, rate-limited logins, email account recovery, and optional two-factor login.
- First-run setup script (`scripts/setup.sh`) for admin creation, theme, and key settings. It never starts the server itself — you run `./postwisp` and the script waits for it and asks you to paste the first-boot token.
- Backups by copying the append-only `data/` directory.
- Unsaved-work guard in the editor: every edit is snapshotted to the browser (per post), leaving with unsaved edits warns first, and reopening offers to restore or discard the snapshot. The status line under the card says "unsaved edits" while any are pending, and Ctrl/Cmd-S saves from anywhere on the page.
- Editor convenience: live slug feedback while you type (`✓ available` / `✗ taken`, with the post's own slug excluded when editing it), a word count with estimated read time, and the drop-anywhere media handling of before.
- Responsive public templates: the header keeps its shape and the page tightens on small screens (720px and 480px breakpoints).
- Reading aids on the post page: clickable heading anchors, a sticky table of contents on wide viewports, and a scroll-progress bar — localized like the rest of the public pages.
