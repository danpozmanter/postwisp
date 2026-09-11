# Changelog
## 0.1.0 - Unreleased
- Self-hosted multi-user blog in one binary: server, JSON API, admin dashboard, and public pages, with embedded terndb storage.
- Markdown writing with live preview in two editors, backed by Milkdown (Crepe).
- Media uploads (photos, video, audio) with content sniffing from magic bytes, `Range`/`ETag` streaming, and per-author media libraries.
- Cover photos from Unsplash search, stored with the post's markdown.
- Themes as four plain HTML templates with inline CSS, re-read from disk on every request.
- Public pages in English, German, French, and Spanish, with localized dates and a per-visitor language switcher.
- Light/dark theme with a site-wide default and a per-visitor toggle, applied pre-paint, with reduced-motion support.
- Accounts: no open registration, admin-created authors, rate-limited logins, email account recovery, and optional two-factor login.
- First-run setup script (`scripts/setup.sh`) for admin creation, theme, and key settings.
- Backups by copying the append-only `data/` directory.
- Unsaved-work guard in both editors: every edit is snapshotted to the browser (per post), leaving with unsaved edits warns first, and reopening offers to restore or discard the snapshot.
- Responsive public templates: the header keeps its shape and the page tightens on small screens (720px and 480px breakpoints).
- Reading aids on the post page: clickable heading anchors, a sticky table of contents on wide viewports, and a scroll-progress bar — localized like the rest of the public pages.
