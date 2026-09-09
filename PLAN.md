# postwisp — Plan

A small, self-hosted, multi-user blog. Gossamer backend with a vendored
terndb engine; single-file admin dashboard (`web/admin.html`).
Goals in priority order: **small**, **fast**, **easy to theme**, **one
process to deploy**.

> **As-built status:** all eight stages are implemented and green
> (`gos build`, `gos test` 174 tests, `gos fmt`, `gos lint` 0 errors —
> only style warnings remain). Deviations from the original plan are
> marked **[deviation]** throughout and collected in §8.

## 1. Architecture

```
┌──────────────────────────────┐      ┌─────────────────────────────┐
│  SvelteKit static build      │      │  postwisp server (Gossamer) │
│  - editor (Tiptap)           │ HTTP │  - http::router             │
│  - login / dashboard UI      ├─────▶│  - sessions, auth           │
│  - theme toggle              │ JSON │  - markdown → HTML renderer │
└──────────────────────────────┘      │  - use engine (embedded)    │
                                      └──────────────┬──────────────┘
                                                     │ in-process
                                              ┌──────▼──────┐
                                              │  terndb   │
                                              └─────────────┘
```

- **Embedded, not the TCP server.** One process, one binary, no socket RTT,
  and the single-writer rule is enforced by the router's single-threaded
  request handling instead of a protocol. The engine is **vendored** into
  `src/` (`engine/`, `sql/`, `kv/`, `codec/` — terndb 0.2.0's module tree) — no external
  dependency in `project.toml`. **[deviation: was a path dependency]**
- **Two data paths, matched to how each is read.** The dashboard and the API
  go through SQL (`SELECT ... ORDER BY ... LIMIT` — what the engine is good
  at). The public site goes through **kv get by slug**: on every save the
  rendered HTML is written under `page/<user>/<slug>` and
  `slug/<user>/<slug>` → post id is registered. A visitor read is the
  engine's O(1) index hit + one pread, no SQL, no markdown, no row decode.
  Deleting or re-slugging a post deletes the kv keys. **[deviation: as
  built, public pages/media/sessions are in-memory maps rebuilt at startup
  from the SQL tables — one engine, one storage path]**
- **Sessions** in a `sessions` table (token, user id, created, expires) or a
  pure-kv map `session/<token>` — kv is enough; sessions need no querying.

## 2. Schema (terndb dialect)

No joins, no `OR`, no list-typed columns, no unique constraints in the engine —
the schema and the code are shaped by that.

```sql
CREATE TABLE users (
    id           INT64,      -- engine-assigned rowid is used, this mirrors it
    username     TEXT,       -- public, unique (enforced app-side)
    email        TEXT,       -- private
    password     TEXT,       -- salted KDF hash (see §8: crc32-chain, not Argon2id)
    role         TEXT,       -- "admin" | "author"
    created_at   DATETIME,
    modified_at  DATETIME
)

CREATE TABLE posts (
    id           INT64,
    user_id      INT64,      -- owner; no join, resolved app-side
    title        TEXT,
    source       TEXT,       -- markdown
    content      TEXT,       -- rendered HTML, regenerated on every save
    tags         TEXT,       -- comma-joined, e.g. "rust,kv"; split app-side
    status       TEXT,       -- "draft" | "published"
    published_at DATETIME,   -- null while draft (stored as 0 = unset epoch)
    slug         TEXT,       -- public, unique (enforced app-side, see §4)
    created_at   DATETIME,
    modified_at  DATETIME
)

CREATE TABLE sessions (
    token      TEXT,         -- random 32 bytes, hex; the kv key is this
    user_id    INT64,
    created_at DATETIME,
    expires_at DATETIME
)
```

kv-only keys (no table): `page/<user>/<slug>` → rendered HTML + title + tags
(for metadata), `slug/<user>/<slug>` → post id (per-user uniqueness registry),
`session/<token>` → user id + expiry, `media/<id>` (+ suffix) → uploaded image
bytes + content type.

**Self-deploy user model.** Single-operator deployment: no open registration.
On first boot with an empty users table, the server prints a one-time setup
URL (`/setup?token=...`) that creates the **admin** account (username, email,
password). The admin creates further **authors** from the dashboard
(`POST /api/users`, admin-only); authors manage only their own posts. Users
table carries a `role` column for this.

**Uniqueness.** The engine has no unique index, and a check-then-insert is two
statements, so the app takes a process-wide `sync::Mutex` around every create /
update / delete that touches slugs or usernames. The engine is single-writer
and the mutex makes check-then-write atomic in-process — which is all that
exists in a one-binary deployment. Usernames are globally unique; **slugs are
unique per user** — the registry key is `slug/<user>/<slug>`, so two users can
each own `my-post` and every write path re-checks that key's absence inside
the lock, failing the save with a 409 if it is taken.

## 3. Backend API

Cookie session auth (`HttpOnly; SameSite=Lax; Secure` behind TLS).

| Method | Path | Purpose |
|---|---|---|
| POST | `/api/setup` | first-boot admin creation via the one-time token |
| POST | `/api/login` | set session cookie |
| POST | `/api/logout` | drop session |
| GET | `/api/me` | username + role for the dashboard header |
| POST | `/api/users` | admin creates an author account |
| GET | `/api/posts?status=&q=&tag=` | own posts; drafts by `modified_at DESC`, published by `published_at DESC`; search filters in-app |
| GET | `/api/posts/<id>` | one post for the editor |
| POST | `/api/posts` | create; validates + renders + claims slug |
| PUT | `/api/posts/<id>` | update; re-renders; slug change re-claims + frees old |
| DELETE | `/api/posts/<id>` | delete + drop kv keys |
| GET | `/api/slug-check?slug=` | live uniqueness check while typing |
| POST | `/api/preview` | markdown → HTML for the editor preview pane (unpublished, auth required) |
| POST | `/api/media` | image upload (multipart); stored in kv, returns `/<user>/media/<id>` URL |
| GET | `/<user>/media/<id>` | serve an uploaded image from kv |
| GET | `/feed.xml` | Atom feed of each author's published posts (per-user, latest N) |
| GET | `/<user>/<slug>` | public page from `page/<user>/<slug>` (the kv get) |

**Password policy** (enforced server-side, mirrored client-side): ≥ 10 chars,
≥ 1 digit, ≥ 1 non-alphanumeric. Hashing: see §8 — a salted crc32-chain KDF
(stdlib has no Argon2id module).

**Search.** The SQL WHERE is an `AND` of scalar comparisons — no `LIKE`, no
`OR` — so text search is an app-side filter over a `SELECT` restricted to the
user's own rows (small tables; a per-user scan of titles + source + tags is
microseconds at blog scale). Tag filtering can use kv keys `tag/<tag>` → id
list if it ever needs to be index-backed; not in v1.

**Slug rules.** Frontend auto-populates from title (lowercase, trim, non
alnum → `-`, collapse repeats, trim `-`), stops auto-following once the user
edits the field by hand. Save is rejected (409) when the slug is taken or
malformed (`^[a-z0-9]+(?:-[a-z0-9]+)*$`, ≤ 96 chars). Slugs are unique
**per user**; the public URL is `/<username>/<slug>`.

**Image uploads.** `POST /api/media` takes a multipart image (jpg/png/webp/
gif), sniffs the real content type from magic bytes, caps size (5 MB) and
stores the bytes in kv under `media/<id>` with a `media/<id>.meta` entry
(content type, owner, sha256, created). Returned URL is
`/<username>/media/<id>`; the editor's image button uploads, then inserts
that URL. Serving checks nothing (public), but the id is a random 128-bit
value, so unguessable. No on-server resizing in v1 — serve what was uploaded.

**Markdown → HTML.** A small Gossamer renderer (headings, emphasis, strong,
strikethrough, links, images, fenced code blocks, blockquotes, lists,
tables, hard breaks) run on every save; result stored in `posts.content` and
`page/<user>/<slug>`. Sanitized: raw HTML in source is escaped, links get
`rel="noopener"`. Kept small on purpose — it is the one piece of "logic" the
platform owns.

**RSS/Atom.** `GET /feed.xml` (per-author, e.g. `/feed.xml?user=` or
`/<user>/feed.xml`) renders the author's most recent N (20) published posts
from the SQL listing — title, permalink, published_at, rendered content.
`Content-Type: application/atom+xml`; a `<link rel="alternate">` in the page
template advertises it.

## 4. Frontend (admin.html, single static page)  **[deviation: was SvelteKit + Tiptap]**

Shipped as one hand-written page, `web/admin.html`, embedded in / served by
the binary at `/admin`. No Node toolchain, no build step — the whole point of
"one process to deploy" is kept honest. All data via the API above.

- **Setup / login views** — first boot shows the one-time setup form
  (auto-redirects when the users table is empty); otherwise the login form.
- **Dashboard (default view after login)** — greeting "Welcome,
  {username}"; two sections: **Drafts** (sorted by modified date, newest
  first) and **Published** (sorted by publish date, newest first); one search
  box filtering both lists live; each row: title, slug link, tags, dates,
  edit / delete; "New post" button. Admins additionally see a Users panel
  (create author, reset password).
- **Editor** — a plain textarea bound to the markdown `source` (stored
  content stays markdown — same goal as the planned Tiptap markdown
  serializer, without the dependency); fields for title, slug (auto-filled
  from title, editable, live uniqueness check), tags (comma input), status
  toggle draft/published; Save (renders + persists) and Preview (renders
  into a styled pane via `/api/preview`); image upload via
  `/api/media` inserts the served URL.
- **Public view** — Gossamer serves `/<user>/<slug>` HTML itself (one read,
  no framework cost). `view` vs `preview` are the same route with the auth
  check deciding.
- **Theme** — one CSS file of custom properties (`--bg --fg --accent --font…`),
  `data-theme="light|dark"` on `<html>`, **dark by default site-wide**; the
  choice is made during `setup.sh` or from the Blog settings page and stored
  under the kv key `postwisp/settings`, so every page (public, listing,
  admin, editor) follows it; a `theme.css` is served at a known path
  (edit the constants in `src/main.gos` or front it with a proxy rule to
  override).

## 5. Stages (all done)

1. **Project skeleton** — `project.toml` (engine vendored into `src/`,
   zero external dependencies), Gossamer `http::serve` + router.
2. **Auth** — users table + roles, one-time `/setup` admin bootstrapping,
   password policy + salted-KDF hashing, sessions, login/logout/me and
   admin user-creation endpoints, cookie handling,
   login rate limiting (§6).
3. **Posts CRUD + slug registry** — schema creation on boot, create/update/
   delete/list/get endpoints, mutex-guarded per-user slug claims,
   published_at handling.
4. **Markdown renderer** — module with unit tests (nesting, code fences, edge
   cases), wired into save and preview.
5. **Dashboard + editor UI** — `web/admin.html`: session handling, dashboard
   lists + search, markdown editor with preview, slug autofill +
   slug-check, admin Users panel.
6. **Media uploads** — endpoint, magic-byte type sniffing, storage +
   serving route, editor image-button integration.
7. **Public serving, feeds + theme** — `/<user>/<slug>` public page,
   `/<user>/feed.xml` Atom, default theme, light/dark toggle, override
   instructions.
8. **Polish** — 404/401 handling, confirm-delete, empty states, `gos lint` /
   `gos fmt` / `gos test` clean (174 tests green), tier parity
   (`gos build` vs `gos run`).

## 8. As-built deviations from the original plan

- **Password hashing** — gossamer's stdlib has no Argon2id / password-KDF
  module; v1 uses a per-hash salted crc32-chain KDF with multiple rounds.
  Acceptable for a small self-hosted instance; revisit if the stdlib grows
  a real password module.
- **Frontend** — SvelteKit + Tiptap replaced by one hand-written
  `web/admin.html` (no Node toolchain, no build step). Functionally
  equivalent coverage of the planned views; the editor is a markdown
  textarea with live preview instead of Tiptap.
- **Storage paths** — the planned separate kv keys (`page/…`, `slug/…`,
  `session/…`, `media/…`) are, as built, in-memory maps rebuilt at startup
  from the SQL tables; the engine and its tables are the single durable
  path. Same read cost class at blog scale, simpler boot/recovery story.
- **Rate limiting** — implemented in-memory (5 failed logins per username
  per 10-minute window → 429), not in the store; a restart clears it,
  which only weakens the lockout by one window.
- **Vendored engine** — terndb is copied into `src/` rather than a path
  dependency; `project.toml` has no dependencies.

## 6. Gaps not in the original ask (v1 decisions + flagged)

Decided for v1, flagged where debatable:

- **Single-operator, no open registration** — decided: first boot creates an
  admin via a one-time setup token; the admin creates authors. Not a gap
  anymore, see §2's user model.
- **Comments deliberately excluded** — small platform; comments are the
  biggest complexity jump (spam, moderation). Intentional omission, not a v1.1
  candidate.
- **Drafts sorted by modified date, published by publish date** — assumed,
  since "sorted by date" was ambiguous.
- **Public URLs carry the username** (`/<user>/<slug>`). Consequence of
  per-user slug uniqueness; also enables per-user feeds.
- **Publishing is a status flip, not a schedule.** No scheduled publishing in
  v1.
- **Backup / export.** terndb is append-only files + `COMPACT`; a `terndb`
  CLI `exec` dump or plain directory copy is the documented backup story —
  should be written down in the README, not improvised.
- **Rate limiting / brute-force lockout on login** — done as built: a
  failed-attempt counter per username (5 fails / 10 min → 429), in-memory;
  see §8.
- **HTTPS.** Out of scope for the binary; the README says "put it behind a
  reverse proxy / caddy".
- **Single process = single point of failure.** Fine for self-hosted; no
  replication story is planned, by design (terndb is single-writer).

## 7. Constraints carried over from terndb

- SQL surface: `CREATE TABLE`, `SELECT` (AND-of-comparisons WHERE, ORDER BY,
  LIMIT, `COUNT(*)`), `INSERT`, `UPDATE`, `DELETE`, prepared statements. No
  `OR`, `LIKE`, joins, subqueries, or unique constraints — app-side filtering
  and the mutex-guarded registry are the compensations, not workarounds.
- Statement-level ACID with a flush per write: fine for a blog's write rate;
  bulk operations should batch.
- TEXT columns for anything list-shaped (tags); DATETIME is epoch-millis UTC.
- No `unwrap_or_else` in code that goes through `gos build --release`; hot
  loops avoid by-value `Vec` parameter passing (see terndb §7).
