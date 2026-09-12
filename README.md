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

   The script never starts the server itself. Start it in another terminal
   (or a service unit) with `./postwisp`, then run the walkthrough: it waits
   for the server, asks you to paste the one-time first-boot token, creates
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
`/dashboard`, press **About page**, and write it like any post (markdown, in
the same full-width editor with the styled/raw toggle). It is then served at `/about` (the first user's — the
admin's) and at `/<user>/about` for every author. About pages never
appear in the post lists or feeds; `templates/about.html` only frames
them. Until someone writes one, a placeholder fills the frame.

That's the whole deployment: one directory, one process (server + admin
dashboard + JSON API + public pages), behind any reverse proxy for TLS.

## Dashboard

The dashboard is served by the binary itself at `/dashboard` (a built-in
page, not one of the templates; the old `/admin` link redirects there).
Authors log in there to manage drafts, published posts, and media; every
editing entry point — **New post**, a post's **edit** link, the **About
page** button — opens the write page at `/editor`, the single place a
post is edited (there is no second embedded editor anymore). Every
logged-in user can also edit their own email and password from the
**Account** button. The admin creates further author accounts; there is
no open registration by design. Failed logins are rate-limited (5
failures per username per 10 minutes).

## File uploads (photos, video, audio)

Both the **Upload** button in the editor and drag-and-drop onto the
writing surface upload a file to your own media library and insert a
reference at the cursor:

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

The editor's **Unsplash** button opens a search modal in the Hashnode
style — type a query, pick a photo, and it becomes the post's cover (or
lands at the cursor in the body). The picked photo is written as the
post's first markdown image, so covers travel with the text everywhere:
the post page hoists it into a header figure, and the home/posts cards
show it as a thumbnail.

Unsplash's API needs a free **Access Key**: create an app at
<https://unsplash.com/oauth/applications> (demo tier: 50 requests/hour)
and paste the key

- when `scripts/setup.sh` asks during first-run setup — it writes the
  key to an `env` file beside the binary (see `README-env.md` in the
  deployment), which the server reads at every boot and hands to the
  editor with your settings, so **no one is ever prompted for a key in
  the browser**,
- on the **Settings** page (`/settings`, "Unsplash access key"), or
- into the picker itself the first time you search.

The key is stored on the server — in `env` (`PW_UNSPLASH_KEY`) or with
the author's settings — so every browser you log in from shares it; a
key pasted straight into the picker is kept in that browser as a
fallback. Without a key, everything else works; the button just asks
for one. An uploaded photo works as a cover too: the editor's cover
row has an **Upload file** button that puts a photo from your computer
straight into the cover slot.

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
- **Editor**: the write page (`/editor`) is one full-width writing card —
  the formatting toolbar (headings, emphasis, code, links, lists, quotes)
  fused into its top edge beside a **Raw markdown** toggle that flips
  between the styled view and the plain source, with a writing surface
  styled like the published post that fills the screen. A **heading
  outline** rides beside the card on wide screens: it lists the post's
  headings, highlights the section you are in, and clicking an entry
  jumps there. Selecting text opens a context toolbar with bold, italic,
  strikethrough, code, links, and heading 1/2/3. The status line counts
  words and estimated read time and says when edits are unsaved;
  Ctrl/Cmd-S saves.

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

## Feeds, favicon, robots

Each author has an Atom feed at `/<user>/feed.xml` (up to 20 published
posts, newest first). Its URLs are absolute — scheme and host are resolved
per request and honour `X-Forwarded-Proto` behind a TLS proxy — and it
carries the `<author>` element RFC 4287 requires, so readers and
validators resolve it outside the browser.

`/favicon.ico` (a 16×32-bpp crescent in the site accent, built into the
binary — nothing to deploy) and `/robots.txt` (public pages indexable,
`/api/`, `/editor`, `/settings`, `/dashboard`, `/setup` disallowed)
answer properly. The dashboard's own assets (`/app.css`,
`/theme-boot.js`, `/milkdown.js`, `/milkdown.css`) carry a strong `ETag`
and answer `304` on revalidation, so an author's browser re-checks them
once every five minutes instead of re-downloading on every page.

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
- `node scripts/check-editor.js` — behavioral check of the `/editor` page's
  inline script (the styled/raw toggle, word count, insert-at-cursor,
  heading outline, slug feedback); plain Node, no packages and no browser
- `node scripts/check-admin.js` — behavioral check of the `/dashboard`
  page's inline script plus a proof of the editor consolidation (no
  embedded editor, every edit link routes to `/editor`)
- `./scripts/build-editor.sh` — rebuild `web/milkdown.js` / `web/milkdown.css`
  from the pinned sources in `vendor-src/` (only needed when the editor bundle
  changes)
- Environment overrides: `PW_DATA` (data dir, default `data/`),
  `PW_TEMPLATES` (public templates, default `templates/`),
  `PW_WEB` (built-in admin/editor pages, default `web/`), `PW_ADDR`
  (bind address, default `127.0.0.1:8080` — set `0.0.0.0:8080` to serve a
  LAN), `PW_UNSPLASH_KEY` (Unsplash access key — also read from an `env`
  file beside the binary, see "Cover photos & images"), and the
  `PW_SMTP_*` set for account recovery (see above)

## Two-factor login over email

Any account with an email address can require a second step at login: tick
**Require a login code from my email** on the Account page. After a correct
password, postwisp mails a 6-digit code to the account's address, and the
session exists only once the code is entered on the login screen. A code
works once and stays valid for five minutes; a login request tolerates at
most three wrong codes, and the server caps how many codes one source can
ask for per ten minutes. The feature uses the same `PW_SMTP_*` settings as
account recovery above; with no relay configured, a two-factor login is
answered with a named 503 instead of a half-open door.

## Password hashing note

Gossamer's stdlib has no password-KDF module; postwisp uses a salted
crc32-chain KDF stretched over multiple rounds. A deliberate v1 deviation,
acceptable for a small self-hosted instance — noted so nobody mistakes it
for a hardened construction.
