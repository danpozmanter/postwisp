# postwisp

**postwisp** (**Post Wisp**) — a small, self-hosted, multi-user blog. One
binary, four editable HTML templates, no Node toolchain. Gossamer backend
with terndb as the embedded storage engine.

## Installing (the short version)

1. Build the deployable directory (on any machine with the `gos` toolchain):

       ./build.sh          # or .\build.ps1 on Windows

   That compiles the release binary and assembles `dist/` containing

       dist/postwisp            the release binary
       dist/templates/          index.html post.html list.html about.html
       dist/web/                built-in admin/editor/setup pages
       dist/scripts/setup.sh    first-run walkthrough

2. Copy the **contents** of `dist/` to your server — binary, `templates/`,
   `web/`, and `scripts/` sitting side by side in one directory.

3. On the server, run

       ./scripts/setup.sh

   It starts the server, captures the one-time first-boot token, creates
   your admin account, logs you in, sets the site theme, and verifies the
   public pages. Password policy: min 10 chars, at least 1 digit and 1
   non-alphanumeric.

4. Edit the templates in `templates/` as you see fit — that's the whole
   theming story. Each is a plain HTML file with inline CSS (no shared
   stylesheets, no build step), and the server reads them from disk on
   every request, so edits show up on the next page load, no restart:

   | Template | Serves | Notes |
   |---|---|---|
   | `templates/index.html` | `/` | home page; lists the latest posts |
   | `templates/post.html` | `/<user>/<slug>` | one published post |
   | `templates/list.html` | `/posts` | all posts, and `/posts?tag=NAME` for one tag |
   | `templates/about.html` | `/about` | the frame around the about post (see below) |

   Placeholders `{{title}}`, `{{site_title}}`, `{{tagline}}`, `{{footer}}`,
   `{{content}}`, `{{date}}`, `{{author_part}}`, `{{tags_part}}`,
   `{{page_title}}`, `{{page_sub}}`, `{{theme_attr}}`, `{{feed_url}}` are
   filled per page; everything else is yours.

   Note there is no `landing.html` or `post-list.html` to find: the home
   page *is* `templates/index.html`, a post *is* `templates/post.html`.

## About pages

The about page is not a file you edit per se — it is a **singleton post**
each author maintains, with the reserved slug `about`. Log in to
`/admin`, press **About page**, and write it like any post (markdown,
live preview). It is then served at `/about` (the first user's — the
admin's) and at `/<user>/about` for every author. About pages never
appear in the post lists or feeds; `templates/about.html` only frames
them. Until someone writes one, a placeholder fills the frame.

That's the whole deployment: one directory, one process (server + admin
dashboard + JSON API + public pages), behind any reverse proxy for TLS.

## Admin

The admin dashboard is served by the binary itself at `/admin` (a built-in
page, not one of the templates). Authors log in there to write posts in
markdown, upload images, and manage drafts. The admin creates further
author accounts; there is no open registration by design. Failed logins
are rate-limited (5 failures per username per 10 minutes).

## Cover photos & images (Unsplash)

Both editors (the write page at `/editor` and the one inside `/admin`)
have an **Unsplash** button: a search modal in the Hashnode style — type a
query, pick a photo, and it becomes the post's cover (or lands at the
cursor in the body). The picked photo is written as the post's first
markdown image, so covers travel with the text everywhere: the post page
hoists it into a header figure, and the home/posts cards show it as a
thumbnail.

Unsplash's API needs a free **Access Key**: create an app at
<https://unsplash.com/oauth/applications> (demo tier: 50 requests/hour)
and paste the key either

- on the **Settings** page (`/settings`, "Unsplash access key"), or
- into the picker itself the first time you search.

The key is stored in your browser only (`localStorage`), never on the
server — each author supplies their own. Without a key, everything else
works; the button just asks for one.

## Look & feel

The design system is shared by the public templates and the built-in
admin pages, in both light and dark mode:

- **Type**: Inter for UI, Source Serif 4 for prose, JetBrains Mono for
  code — fluid `clamp()`-based sizes so text scales with the viewport.
- **Theme**: dark by default; the site-wide choice is set on the Settings
  page, and each visitor's own toggle (in the header) takes precedence
  and persists. No flash of the wrong theme — it is applied pre-paint.
- **Texture**: a subtle grain overlay and a soft accent glow; cards have
  layered borders/shadows. Everything honours `prefers-reduced-motion`.
- **Reading first**: 44rem measure, 1.78 line-height for prose, generous
  spacing, WCAG-leaning contrast in both modes.

The public templates inline the same token set the admin stylesheet
(`/app.css`) uses, so a page is one request with no stylesheet
dependency — the tokens at the top of each file are the theming surface.

## HTTPS

TLS is out of scope for the binary. Put it behind a reverse proxy, e.g.
Caddy:

    example.com {
        reverse_proxy 127.0.0.1:8080
    }

The session cookie is not marked `Secure` on purpose, so first-run setup
over plain `http://127.0.0.1:8080` works. Behind a TLS proxy the browser
still only sends it over the proxied HTTPS origin.

## Backup

Storage is append-only files under `data/`. With the server stopped (or
from a filesystem snapshot), copy the `data/` directory verbatim.

## Development

- `gos run .` — run from source (templates then load from `./templates/`)
- `gos test` — test suite
- `gos build` — debug binary
- Environment overrides: `PW_DATA` (data dir, default `data/`),
  `PW_TEMPLATES` (public templates, default `templates/`),
  `PW_WEB` (built-in admin/editor pages, default `web/`)

## Password hashing note

Gossamer's stdlib has no password-KDF module; postwisp uses a salted
crc32-chain KDF stretched over multiple rounds. A deliberate v1 deviation,
acceptable for a small self-hosted instance — noted so nobody mistakes it
for a hardened construction.
