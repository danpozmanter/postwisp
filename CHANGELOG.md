# Changelog
## 0.1.1 - 2026-09-24
- Updated to Gossamer 0.64.0.
- Updated the vendored terndb storage engine to 0.3.0.

## 0.1.0 - 2026-09-17
- Self-hosted multi-user blog in one binary: server, JSON API, admin dashboard, and public pages.
- Markdown editor at `/editor` with a styled/raw toggle and a heading outline.
- Media uploads for photos, video, and audio.
- Cover photos picked from Unsplash search.
- Four plain HTML templates, hot-reloaded from disk.
- Public pages in English, German, French, and Spanish, with localized dates.
- Light/dark theme with a per-visitor toggle.
- Admin-created authors with rate-limited logins, email recovery, and optional 2FA.
- Atom feeds per author.
- Back up by copying the append-only `data/` directory.
- First-run setup script for admin creation and key settings.
