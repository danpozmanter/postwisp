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
   | `templates/index.html` | `/` | home page; the **3 most recent** posts |
   | `templates/post.html` | `/<user>/<slug>` | one published post |
   | `templates/list.html` | `/posts` | all posts, and `/posts?tag=NAME` for one tag |
   | `templates/about.html` | `/about` | the frame around the about post (see below) |

   Placeholders `{{title}}`, `{{site_title}}`, `{{tagline}}`, `{{footer}}`,
   `{{content}}`, `{{date}}`, `{{author_part}}`, `{{tags_part}}`,
   `{{theme_attr}}`, `{{feed_url}}` are
   filled per page; everything else is yours.

   Note there is no `landing.html` or `post-list.html` to find: the home
   page *is* `templates/index.html`, a post *is* `templates/post.html`.

## About pages

The about page is not a file you edit per se — it is a **singleton post**
each author maintains, with the reserved slug `about`. Log in to
`/dashboard`, press **About page**, and write it like any post (markdown,
live preview). It is then served at `/about` (the first user's — the
admin's) and at `/<user>/about` for every author. About pages never
appear in the post lists or feeds; `templates/about.html` only frames
them. Until someone writes one, a placeholder fills the frame.

That's the whole deployment: one directory, one process (server + admin
dashboard + JSON API + public pages), behind any reverse proxy for TLS.

## Dashboard

The dashboard is served by the binary itself at `/dashboard` (a built-in
page, not one of the templates; the old `/admin` link redirects there).
Authors log in there to write posts in markdown, upload files, and manage
drafts; every logged-in user can also edit their own email and password
from the **Account** button. The admin creates further
author accounts; there is no open registration by design. Failed logins
are rate-limited (5 failures per username per 10 minutes).

## File uploads (photos, video, audio)

The **Upload** button in both editors (and drag-and-drop onto the source
pane) uploads a file to your own media library and inserts a reference at
the cursor:

- **Photos** — `![alt](/<user>/media/<id>)`, rendered as `<img>`; the
  first image in a post is its cover.
- **Video** — `![alt](/<user>/media/<id> video)`, rendered as a
  `<video controls>` player.
- **Audio** — `![alt](/<user>/media/<id> audio)`, rendered as an
  `<audio controls>` player.

A reference to any external URL ending in `.mp4` `.webm` `.mov` `.m4v`
(or `.mp3` `.ogg` `.oga` `.wav` `.m4a` `.flac`) embeds a player too; the
` video` / ` audio` hint is only needed for extensionless URLs like the
media library's own. Supported uploads: jpg, png, webp, gif (max 5 MB);
mp4, webm, mp3, ogg, wav, m4a (max 50 MB).

Security posture, by design:

- The **content type is sniffed from the file's magic bytes** at upload —
  what the browser claims is never trusted — and anything that is not a
  known signature is refused. Only `image/*`, `video/*`, and `audio/*`
  types are ever served, with `X-Content-Type-Options: nosniff`, so an
  upload can never become stored HTML/JS on your origin.
- Markdown rendering is sanitized as before: raw HTML in source is
  escaped, `javascript:` and `data:` URLs are blocked, links carry
  `rel="noopener"` — including player sources.
- Media ids are random 128-bit values; only the owning author (or an
  admin) can list or delete them from the dashboard's **Media** panel,
  and delete is refused with the post's title while any post still
  embeds the file.

Efficiency: media files are served with `Cache-Control: immutable` and a
strong `ETag` (exact revalidation answers `304`), and every response —
whole or partial — streams from disk in 256 KB chunks, so a 50 MB video
never lands whole in memory. `Range` requests (with `If-Range`) are
served as `206` partial content, which is what lets browsers seek in a
video and iOS Safari play it at all.

## Cover photos & images (Unsplash)

Both editors (the write page at `/editor` and the one inside `/dashboard`)
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

A post's header image is the first markdown image of its source, and it
is the only image that gets special treatment: the post page hoists it
into a header figure, and the home page / post list cards show it as a
thumbnail. **A post with no header image shows no image frame anywhere**
— not on its page, not in a card, just the text. The editor also accepts
an uploaded image as the header: upload any image in the editor, move
its reference to the top of the markdown (or just make it the first
image), and it becomes the header.

## Look & feel

The design system is shared by the public templates and the built-in
admin pages, in both light and dark mode:

- **Type**: Atkinson Hyperlegible for UI, Source Serif 4 for prose,
  JetBrains Mono for code — fluid `clamp()`-based sizes so text scales
  with the viewport. Atkinson Hyperlegible (Braille Institute, free for
  any use) is a legibility-first design — unambiguous letterforms
  (Il1, O0), open counters, distinct pairs — and the best-supported
  "easier to read" default available on Google Fonts; it falls back to
  the system UI stack when offline.
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

## Internationalization

The public pages (home, posts list, post, about, and the error pages)
are translated into **English, German, French, and Spanish** — labels,
headings, empty states, and the error-page text. Which language a
visitor sees is decided in this order:

1. **Their own choice** — the language switcher in the site header sets
   a `postwisp-lang` cookie for a year.
2. **Their browser** — the first supported primary subtag of
   `Accept-Language`.
3. **The site default** — the Site language selector on the Settings
   page (English until someone changes it).

The switcher's options always show each language's native name
("Deutsch", "Español"), so a visitor can find their own whatever the
current language is. Dates are localized too — the server renders post
dates and the browser renders card dates in the same locale shape
(en "March 5, 2024", de "5. März 2024"), so the two agree on a page.

Your own content (post titles, tags, the about text, the tagline,
footer, and everything on the dashboard) is yours and is never
translated or overridden. Adding a language is one row per message in
the `i18n_catalog` in `src/main.gos` plus its month names; the test
suite fails if a row or translation is missing or is an English copy.

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

## Account recovery over email

A user who loses their username or password can recover both from the
login screen: **Lost username or password?** takes the email address they
signed up with, and the account it belongs to receives one mail carrying
the username plus a single-use link (valid one hour) that sets a new
password and logs straight in. The mail names the username, so one flow
covers both cases.

Recovery needs an SMTP relay, configured through the environment (never
stored in the data directory or reachable from the settings API):

    PW_SMTP_HOST   mail server hostname; recovery answers 503 while unset
    PW_SMTP_PORT   port (default 587)
    PW_SMTP_USER   SMTP username; leave empty for an unauthenticated relay
    PW_SMTP_PASS   password for PW_SMTP_USER
    PW_SMTP_FROM   envelope sender (default "postwisp@<host>")

Behaviour worth knowing:

- The answer to a recovery request is always the same generic "on its
  way", whether or not the address belongs to an account — the endpoint
  never confirms or denies an address.
- Requests are capped per source (5 per 10 minutes, shared with the
  login-attempt window), a stuck relay times out after 8 seconds instead
  of holding the server, and a used or expired link is dead: a replayed
  one answers "invalid or expired, request a new one".
- Setting a new password revokes every session the account had open.

## Development

- `gos run .` — run from source (templates then load from `./templates/`)
- `gos test` — test suite
- `gos build` — debug binary
- Environment overrides: `PW_DATA` (data dir, default `data/`),
  `PW_TEMPLATES` (public templates, default `templates/`),
  `PW_WEB` (built-in admin/editor pages, default `web/`), and the
  `PW_SMTP_*` set for account recovery (see above)

## Password hashing note

Gossamer's stdlib has no password-KDF module; postwisp uses a salted
crc32-chain KDF stretched over multiple rounds. A deliberate v1 deviation,
acceptable for a small self-hosted instance — noted so nobody mistakes it
for a hardened construction.
