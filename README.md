# postwisp

**postwisp** is a small, self-hosted, multi-user blog: one binary, four
editable HTML templates, no Node toolchain. Gossamer backend, terndb as the
embedded storage engine.

**[Full documentation](https://danpozmanter.github.io/postwisp)** — install,
theming, media, accounts, operations.

## Features

- One binary — server, admin dashboard, JSON API, and public pages in a
  single process.
- **Single editor** at `/editor`: styled/raw toggle, heading outline, word
  count, Ctrl/Cmd-S save.
- **Media uploads** for photo, video, and audio — content type sniffed from
  magic bytes, served with `Range`/`206` streaming support.
- **Unsplash covers** — search and pick a photo as a post's header image.
- **Four-template theming** — plain HTML files, re-read from disk on every
  request; edits go live without a restart.
- **i18n** — public pages in English, German, French, and Spanish, with
  localized dates.
- **Light & dark theme** with a per-visitor toggle and a site-wide default.
- **Accounts** — admin-created authors (no open registration), rate-limited
  logins, email recovery, optional email two-factor login.
- **Atom feeds** per author, with absolute URLs that honour
  `X-Forwarded-Proto`.
- **Append-only storage** under `data/` — back up by copying the directory.

## Requirements

To **build** postwisp you need:

- A Linux, macOS, or Windows machine.
- The [Gossamer](https://github.com/gossamer-lang/gossamer) toolchain,
  `^v0.58.3`:

  ```sh
  curl -fsSL https://raw.githubusercontent.com/gossamer-lang/gossamer/main/scripts/install.sh | sh
  ```

  This installs `gos` into `~/.local/bin` — make sure that directory is on
  your `PATH`.

Node.js is **not** needed to build or run postwisp; it is only used for the
optional development checks (see [Development](#development)).

## Install

1. **Install Gossamer** with the one-liner above and verify `gos --version`.
2. **Clone and build** the deployable `dist/` directory:

   ```sh
   git clone https://github.com/danpozmanter/postwisp
   cd postwisp
   ./build.sh              # Windows: .\build.ps1
   ```

3. **Deploy**: copy the **contents** of `dist/` to your server — binary,
   `templates/`, `web/`, and `scripts/` side by side in one directory.
4. **Set up** on the server:

   ```sh
   ./scripts/setup.sh
   ```

   The script asks for a bind address (default `127.0.0.1:8080`, loopback —
   ready for a reverse proxy), and whether to install a **systemd system
   unit** (via sudo) or a **user unit** (no root; `linger` enabled so it
   survives logout). Either way it then verifies the server answers
   `curl /status` with `postwisp ok`, and walks you through first run: paste
   the one-time token from the console (`journalctl -u postwisp`, or
   `data/server.log` when run by hand), create the admin account — password
   policy: minimum 10 characters, at least 1 digit and 1 non-alphanumeric —
   then set the theme and optionally an Unsplash key.

5. **Manage the service**:

   ```sh
   systemctl status postwisp            # or: systemctl --user status postwisp
   systemctl restart postwisp           # or: systemctl --user restart postwisp
   systemctl stop postwisp              # or: systemctl --user stop postwisp
   journalctl -u postwisp -f            # follow the logs
   curl http://127.0.0.1:8080/status    # "postwisp ok"
   ```

## Templates

Each template is a plain HTML file with inline CSS (no shared stylesheets, no
build step). The server reads them from disk on every request, so edits show
up on the next page load — no restart.

| Template | Serves | Notes |
|---|---|---|
| `templates/index.html` | `/` | home page; the 3 most recent posts |
| `templates/post.html` | `/<user>/<slug>` | one published post |
| `templates/list.html` | `/posts` | all posts, and `/posts?tag=NAME` for one tag |
| `templates/about.html` | `/about` | the frame around the about post |

Placeholders `{{title}}`, `{{site_title}}`, `{{tagline}}`, `{{footer}}`,
`{{content}}`, `{{date}}`, `{{author_part}}`, `{{tags_part}}`,
`{{theme_attr}}`, `{{feed_url}}` are filled per page; everything else is
yours. The about page is a singleton post (reserved slug `about`) each author
writes like any other; `templates/about.html` only frames it.

## HTTPS

TLS is out of scope for the binary — put it behind a reverse proxy, e.g.
Caddy:

```
example.com {
    reverse_proxy 127.0.0.1:8080
}
```

The session cookie is not marked `Secure` on purpose so first-run setup over
plain `http://127.0.0.1:8080` works; behind a TLS proxy the browser only
sends it over the HTTPS origin.

## Backup

Storage is append-only files under `data/`. With the server stopped (or from
a filesystem snapshot), copy the `data/` directory verbatim.

## Development

- `gos run .` — run from source (templates load from `./templates/`)
- `gos test` — test suite
- `node scripts/check-editor.js` / `check-admin.js` / `check-theme.js` —
  behavioral checks of the built-in pages (plain Node, no packages)
- `./scripts/build-editor.sh` — rebuild the editor bundle from `vendor-src/`
  (only needed when it changes)

Environment overrides: `PW_DATA` (data dir, `data/`), `PW_TEMPLATES`
(templates, `templates/`), `PW_WEB` (built-in pages, `web/`), `PW_ADDR` (bind
address, `127.0.0.1:8080`), `PW_UNSPLASH_KEY` (Unsplash access key; also read
from an `env` file beside the binary), and `PW_SMTP_HOST`, `PW_SMTP_PORT`,
`PW_SMTP_USER`, `PW_SMTP_PASS`, `PW_SMTP_FROM` for the email relay used by
account recovery and two-factor login.

## License

Apache-2.0. Password hashing uses a salted crc32-chain KDF — a deliberate v1
deviation, noted so nobody mistakes it for a hardened construction.

---

Full documentation: <https://danpozmanter.github.io/postwisp>
