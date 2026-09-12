# The `env` file — server-side configuration

postwisp reads a file named `env` from the directory it is started in,
at every boot. `scripts/setup.sh` writes it for you when you paste an
Unsplash Access Key during first-run setup; this note is for adding or
changing the key later by hand.

## Format

One `KEY=VALUE` per line. Blank lines and lines starting with `#` are
ignored. Values are taken verbatim — no quotes, no shell expansion.

    # postwisp environment
    PW_UNSPLASH_KEY=your-access-key-here

## Install it on a server

1. Create the file next to the `postwisp` binary (the directory you
   copied `dist/`'s contents into):

       nano env

   with the content above, then restrict it to the service account:

       chmod 600 env

2. Restart the server the way you started it — Ctrl-C in its terminal
   and `./postwisp` again, or `systemctl restart postwisp` for a unit.
   The file is read at boot, so a running server does not see edits.

That is the whole install. The key is served to the editor with your
own logged-in settings, so the Unsplash search and cover-photo picker
work from every browser you log in from — **no one is ever asked to
paste a key in the browser**.

## What can live in it

| Key | Meaning |
|---|---|
| `PW_UNSPLASH_KEY` | Unsplash Access Key for the editor's image search and cover picker |

Precedence: a real `PW_UNSPLASH_KEY` in the process environment (a
systemd `Environment=` line, for instance) beats the file, and a key
saved on the Settings page beats both. The `PW_SMTP_*` settings for
account recovery are read from the process environment only — they are
deliberately never stored in a file next to the binary.

## Security notes

- The file holds a secret: keep it out of any web-served directory and
  never commit it to version control.
- It lives beside the binary, not inside `data/`, so a data-directory
  backup never carries the key.
- Only the logged-in author's own settings API ever sees it; the public
  settings endpoint serves the same JSON without the key.
