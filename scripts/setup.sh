#!/usr/bin/env bash
# scripts/setup.sh — interactive first-run walkthrough for a postwisp dist
# directory (binary + templates/ + this script). Run it ON THE SERVER, from
# the directory you copied dist/'s contents into.
# Covers: you start the server yourself -> create admin -> login -> choose
# site theme -> verify the public pages. The script never starts, stops, or
# restarts the server.
set -euo pipefail

BASE_URL="http://127.0.0.1:8080"
DATA_DIR="data"
JAR="/tmp/postwisp-cookies.txt"
BIN="./postwisp"

step() { printf '\n\033[1;36m== %s ==\033[0m\n' "$*"; }
ok()   { printf '\033[1;32mOK:\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31mFAILED:\033[0m %s\n' "$*" >&2; exit 1; }
ask()  { read -r -p "$1 " ans; echo "$ans"; }
# ask_secret: like ask, but the typed text is not echoed (password entry)
ask_secret() {
    local ans
    read -r -s -p "$1 " ans
    echo >&2
    printf '%s' "$ans"
}
# minimal JSON string escaping so quotes/backslashes in user input survive
json() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

step "1/6 Prerequisites"
[ -x "$BIN" ] || die "no postwisp binary in this directory (expected ./$BIN)"
command -v curl >/dev/null 2>&1 || die "curl not found. Install curl first."
[ -f templates/index.html ] || die "templates/ is missing next to the binary."
ok "postwisp binary and templates present."

step "2/6 Check the server is running"
echo "The script does not start the server itself. In another terminal (or a"
echo "service unit), start it from this directory:"
echo
echo "    $BIN"
echo
echo "It stores everything in ./${DATA_DIR}/ and, on first boot, prints a"
echo "one-time setup URL containing a token. If ${DATA_DIR}/ already exists"
echo "with users in it, setup is already done — you can still use this script"
echo "to log in and set the theme/key."
echo "Waiting for $BASE_URL (press Ctrl-C to give up)..."
rm -f "$JAR"
UP=0
for _ in $(seq 1 60); do
    if curl -sf -o /dev/null "$BASE_URL/setup"; then UP=1; break; fi
    sleep 0.5
done
[ "$UP" = 1 ] || die "no server on $BASE_URL — start it with ./$BIN and rerun this script"
ok "Server found at $BASE_URL."
BOOT_LOG=""
TOKEN="$(ask "Paste the setup token from the server's console (or press Enter if the database is already initialized):")"
if [ -n "$TOKEN" ]; then
    ok "Setup token captured: $TOKEN"
fi

step "3/6 Create the admin account"
if [ -z "$TOKEN" ]; then
    echo "No token given, so the admin account is assumed to exist already."
    USERNAME="$(ask "Existing admin username:")"
    PASSWORD="$(ask_secret "Password:")"
else
    while true; do
        USERNAME="$(ask "Admin username (lowercase letters/digits/-/_, or press Enter to abort):")"
        if [ -z "$USERNAME" ]; then
            die "aborted at user request (no admin account created)"
        fi
        EMAIL="$(ask "Admin email:")"
        PASSWORD="$(ask_secret "Password (min 10 chars, 1 digit, 1 non-alphanumeric):")"
        RESP="$(curl -s -w '\n%{http_code}' -X POST "$BASE_URL/api/setup" \
            -H 'Content-Type: application/json' \
            -d "{\"token\":\"$(json "$TOKEN")\",\"username\":\"$(json "$USERNAME")\",\"email\":\"$(json "$EMAIL")\",\"password\":\"$(json "$PASSWORD")\"}")"
        CODE="$(echo "$RESP" | tail -n1)"
        if [ "$CODE" = "200" ]; then
            break
        fi
        printf '\033[1;31mFAILED:\033[0m setup rejected (HTTP %s): %s\n' "$CODE" "$(echo "$RESP" | head -n1)"
        CHOICE="$(ask "Press Enter to re-enter the details, or type 'exit' to quit:")"
        if [ "$CHOICE" = "exit" ]; then
            die "aborted at user request (no admin account created)"
        fi
    done
    ok "Admin account '$USERNAME' created."
fi

step "4/6 Log in"
RESP="$(curl -s -w '\n%{http_code}' -c "$JAR" -X POST "$BASE_URL/api/login" \
    -H 'Content-Type: application/json' \
    -d "{\"username\":\"$(json "$USERNAME")\",\"password\":\"$(json "$PASSWORD")\"}")"
CODE="$(echo "$RESP" | tail -n1)"
[ "$CODE" = "200" ] || die "login rejected (HTTP $CODE): $(echo "$RESP" | head -n1)"
ok "Logged in; session cookie saved to $JAR."
curl -sf -b "$JAR" "$BASE_URL/api/me" >/dev/null || die "session check failed (/api/me)."

step "5/6 Choose the site theme"
echo "postwisp is dark by default. This choice applies to the whole site"
echo "(public pages, the post listing, and the admin dashboard)."
THEME="$(ask "Theme — dark or light? [dark]:")"
[ -z "$THEME" ] && THEME="dark"
while [ "$THEME" != "dark" ] && [ "$THEME" != "light" ]; do
    THEME="$(ask "Please type 'dark' or 'light':")"
    [ -z "$THEME" ] && THEME="dark"
done
RESP="$(curl -s -w '\n%{http_code}' -b "$JAR" -X PUT "$BASE_URL/api/settings" \
    -H 'Content-Type: application/json' \
    -d "{\"theme\":\"$THEME\"}")"
CODE="$(echo "$RESP" | tail -n1)"
[ "$CODE" = "200" ] || die "theme save rejected (HTTP $CODE): $(echo "$RESP" | head -n1)"
ok "Site theme set to '$THEME'."

step "6/6 Unsplash access key (optional)"
echo "The editor's image search and cover-photo picker use the Unsplash API."
echo "A free Access Key comes from creating an app at"
echo "  https://unsplash.com/oauth/applications  (demo tier: 50 requests/hour)."
UKEY="$(ask "Paste your Unsplash Access Key (or press Enter to skip):")"
if [ -n "$UKEY" ]; then
    RESP="$(curl -s -w '\n%{http_code}' -b "$JAR" -X PUT "$BASE_URL/api/settings" \
        -H 'Content-Type: application/json' \
        -d "{\"unsplash_key\":\"$(json "$UKEY")\"}")"
    CODE="$(echo "$RESP" | tail -n1)"
    [ "$CODE" = "200" ] || die "Unsplash key save rejected (HTTP $CODE): $(echo "$RESP" | head -n1)"
    ok "Unsplash key saved with the server settings."
else
    echo "Skipped — you can add one later on the Settings page ($BASE_URL/settings)."
fi

echo
echo "Verifying public output..."
curl -sf -o /dev/null "$BASE_URL/" || die "home page not served at /"
ok "Home:            $BASE_URL/          (templates/index.html)"
curl -sf -o /dev/null "$BASE_URL/posts" || die "post listing not served at /posts"
ok "Post listing:    $BASE_URL/posts     (templates/list.html)"
curl -sf -o /dev/null "$BASE_URL/about" || die "about page not served at /about"
ok "About:           $BASE_URL/about     (templates/about.html)"

echo
ok "Setup complete."
echo
echo "Your blog (the server you started is still running):"
echo "  Home:             $BASE_URL/"
echo "  All posts:        $BASE_URL/posts  (?tag=NAME lists one tag)"
echo "  About:            $BASE_URL/about"
echo "  Dashboard:        $BASE_URL/dashboard"
echo
echo "To stop the server:  however you started it (Ctrl-C in its terminal,"
echo "or stop the service unit)."
echo "To start it again:   $BIN"
echo
echo "Last step: edit the templates in ./templates/ as you see fit — the"
echo "server reads them from disk, so changes show up on the next page"
echo "load, no restart needed."
