#!/usr/bin/env bash
# scripts/setup.sh — first-run setup for a postwisp dist directory
# (binary + templates/ + web/ + this script). Run it ON THE SERVER, from
# the directory you copied dist/'s contents into.
#
# On Linux the script does the whole deployment: it detects the OS and the
# init system, installs and starts postwisp as a service (a systemd system
# unit via sudo, or a systemd user unit on a rootless/shared VPS — with
# linger so it survives logout), waits until the server answers its
# /status health endpoint, then runs the first-run walkthrough: create
# admin -> login -> choose site theme -> optional Unsplash key -> verify
# the public pages. On non-Linux hosts (or without systemd, if you prefer)
# it offers to start the server by hand and walks through the same steps.
set -euo pipefail

DATA_DIR="data"
JAR="/tmp/postwisp-cookies.txt"
SERVICE_NAME="postwisp"

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

# ---------------------------------------------------------------- 1/7 ---
step "1/7 Detect environment"

# Resolve this script's own location so the app directory (the one holding
# the binary, templates/, and web/) is found whether the script is run as
# ./scripts/setup.sh, scripts/setup.sh, or by absolute path.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$APP_DIR"

# Find the postwisp binary: a copied dist/ directory (the normal server
# case), the checkout right after ./build.sh, or a local dev build.
BIN=""
for CANDIDATE in "$APP_DIR/postwisp" "$APP_DIR/dist/postwisp" "$APP_DIR/target/debug/postwisp"; do
    if [ -f "$CANDIDATE" ] && [ -x "$CANDIDATE" ]; then
        BIN="$CANDIDATE"
        break
    fi
done
if [ -z "$BIN" ]; then
    GOS_HINT="run ./build.sh first"
    command -v gos >/dev/null 2>&1 && GOS_HINT="run ./build.sh (or gos build) first"
    die "no postwisp binary found in $APP_DIR/postwisp, $APP_DIR/dist/postwisp, or $APP_DIR/target/debug/postwisp — $GOS_HINT"
fi
if [ "$BIN" != "$APP_DIR/postwisp" ]; then
    echo "NOTE: using a build from the project tree; a production server wants the contents of dist/ copied to its own directory."
fi
ok "Found: $BIN"

OS="$(uname -s)"
if [ "$OS" != "Linux" ]; then
    echo "This looks like $OS. Automatic service installation is Linux-only"
    echo "(systemd/OpenRC init scripts); falling back to manual mode: the"
    echo "walkthrough below still works once you have the server running"
    echo "yourself with:  $BIN"
    MANUAL_MODE=1
else
    MANUAL_MODE=0
fi

[ -f "$APP_DIR/templates/index.html" ] || die "templates/ is missing at $APP_DIR/templates — copy the whole contents of dist/ (binary, templates/, web/, scripts/), not just the binary"
[ -d "$APP_DIR/web" ] || die "web/ is missing at $APP_DIR/web — the built-in admin/editor pages live there; copy the whole contents of dist/"
command -v curl >/dev/null 2>&1 || die "curl not found. Install curl first (e.g. apt install curl)."
ok "System: $OS; app directory: $APP_DIR"
ok "Found: $APP_DIR/templates/"
ok "Found: $APP_DIR/web/"

# ---------------------------------------------------------------- 2/7 ---
step "2/7 Choose the bind address"
echo "By default the server listens on 127.0.0.1:8080 — your machine only,"
echo "with a reverse proxy (Caddy/nginx for HTTPS) or an SSH tunnel in"
echo "front. That is the normal shape for a VPS. Choosing 0.0.0.0:8080"
echo "instead serves your LAN / public interface directly (no TLS)."
PW_ADDR="$(ask "Bind address — press Enter for 127.0.0.1:8080, or type 0.0.0.0:8080:")"
[ -z "$PW_ADDR" ] && PW_ADDR="127.0.0.1:8080"
BASE_URL="http://$PW_ADDR"
ok "The server will listen on $PW_ADDR (health endpoint: $BASE_URL/status)."

# ---------------------------------------------------------------- 3/7 ---
SYSTEMD_UNIT=""
START_CMD=""
STOP_CMD=""
SERVICE_STATUS_CMD=""
LOG_HINT=""

write_unit() {
    # $1 = "system" or "user"; prints the unit path. The unit content is
    # identical apart from the [Install] target; all paths are absolute
    # so the service works no matter where it is started from.
    local kind="$1"
    local wanted
    if [ "$kind" = "system" ]; then wanted="multi-user.target"; else wanted="default.target"; fi
    cat <<UNIT
[Unit]
Description=postwisp blog server
After=network.target

[Service]
ExecStart=$BIN
WorkingDirectory=$APP_DIR
Environment=PW_ADDR=$PW_ADDR
Restart=on-failure
RestartSec=2

[Install]
WantedBy=$wanted
UNIT
}

if [ "$MANUAL_MODE" = 0 ]; then
    step "3/7 Set up postwisp as a service (optional)"
    echo "A service keeps postwisp running on a server (starts at boot,"
    echo "restarts after crashes). You do NOT need one to run postwisp"
    echo "locally — choosing 'no' simply starts the server in the"
    echo "background here, storing everything in ./data/."
    WANT_SERVICE="$(ask "Set up postwisp as a service? Press Enter for no (run locally), or type 'yes':")"
    case "$WANT_SERVICE" in
        yes|y) ;;
        *) MANUAL_MODE=1 ;;
    esac
fi

# Still 0 only when 'yes' was answered above (non-Linux hosts and
# decliners already have MANUAL_MODE=1).
if [ "$MANUAL_MODE" = 0 ]; then
    # --- detect the init system -------------------------------------------
    INIT_SYSTEM="unknown"
    if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
        INIT_SYSTEM="systemd"
    elif [ -e /proc/1/comm ] && grep -qi systemd /proc/1/comm 2>/dev/null; then
        INIT_SYSTEM="systemd"
    elif command -v rc-service >/dev/null 2>&1; then
        INIT_SYSTEM="openrc"
    elif [ -x /etc/init.d/cron ] || [ -d /etc/init.d ]; then
        INIT_SYSTEM="sysvinit"
    fi

    if [ "$INIT_SYSTEM" = "openrc" ] || [ "$INIT_SYSTEM" = "sysvinit" ]; then
        echo "This server uses $INIT_SYSTEM. Automatic installation covers"
        echo "systemd only — here is a manual unit to adapt:"
        echo
        write_unit system
        echo
        echo "Install it as an $INIT_SYSTEM service yourself, or just run the"
        echo "server in the background (the next question offers that)."
        INIT_SYSTEM="none"
    fi

    if [ "$INIT_SYSTEM" = "systemd" ]; then
        # --- system unit (with sudo) or user unit (rootless) --------------
        UNIT_KIND=""
        if [ "$(id -u)" = "0" ]; then
            UNIT_KIND="system"
        else
            # Not root: ask whether sudo is available for a system unit,
            # or whether this is a rootless/shared VPS wanting a user unit.
            echo "You are not root. postwisp can be installed either way:"
            echo "  - a SYSTEM service (starts at boot, managed with sudo), or"
            echo "  - a USER service (no root needed — right for a shared VPS;"
            echo "    with 'linger' it keeps running after you log out)."
            CHOICE="$(ask "Install a system service or a user service? [system/user]:")"
            case "$CHOICE" in
                user) UNIT_KIND="user" ;;
                system|"" ) UNIT_KIND="system" ;;
                *) die "please answer 'system' or 'user'" ;;
            esac
            if [ "$UNIT_KIND" = "system" ] && ! sudo -n true 2>/dev/null; then
                echo "Installing a system service needs sudo — you may be asked"
                echo "for your password once, when the unit file is written."
            fi
        fi

        if [ "$UNIT_KIND" = "system" ]; then
            UNIT_PATH="/etc/systemd/system/${SERVICE_NAME}.service"
            if [ -f "$UNIT_PATH" ]; then
                echo "A system unit already exists at $UNIT_PATH."
                KEEP="$(ask "Overwrite it? Press Enter to keep it and just (re)start, or type 'overwrite':")"
                if [ "$KEEP" = "overwrite" ]; then
                    write_unit system | sudo tee "$UNIT_PATH" >/dev/null \
                        || die "could not write $UNIT_PATH (sudo declined?)"
                    ok "Unit written: $UNIT_PATH"
                else
                    ok "Keeping the existing unit."
                fi
            else
                write_unit system | sudo tee "$UNIT_PATH" >/dev/null \
                    || die "could not write $UNIT_PATH (sudo declined?)"
                ok "Unit written: $UNIT_PATH"
            fi
            echo "Reloading systemd and starting the service (may ask for a password)..."
            sudo systemctl daemon-reload || die "systemctl daemon-reload failed"
            sudo systemctl enable --now "$SERVICE_NAME" || die "could not enable/start $SERVICE_NAME — try: sudo systemctl status $SERVICE_NAME"
            START_CMD="sudo systemctl restart $SERVICE_NAME"
            STOP_CMD="sudo systemctl stop $SERVICE_NAME"
            SERVICE_STATUS_CMD="sudo systemctl status $SERVICE_NAME --no-pager"
            LOG_HINT="journalctl -u $SERVICE_NAME -f"
            ok "postwisp installed as a system service (starts on boot)."
        else
            UNIT_DIR="$HOME/.config/systemd/user"
            UNIT_PATH="$UNIT_DIR/${SERVICE_NAME}.service"
            mkdir -p "$UNIT_DIR"
            if [ -f "$UNIT_PATH" ]; then
                echo "A user unit already exists at $UNIT_PATH."
                KEEP="$(ask "Overwrite it? Press Enter to keep it and just (re)start, or type 'overwrite':")"
                if [ "$KEEP" = "overwrite" ]; then
                    write_unit user > "$UNIT_PATH" || die "could not write $UNIT_PATH"
                    ok "Unit written: $UNIT_PATH"
                else
                    ok "Keeping the existing unit."
                fi
            else
                write_unit user > "$UNIT_PATH" || die "could not write $UNIT_PATH"
                ok "Unit written: $UNIT_PATH"
            fi
            # Linger: keep the user service alive after you log out.
            if loginctl enable-linger "$USER" 2>/dev/null; then
                ok "Linger enabled — the service survives logout."
            else
                echo "NOTE: could not enable linger automatically (needs an"
                echo "admin). Ask your host to run:"
                echo "    sudo loginctl enable-linger $USER"
                echo "Until then the service stops when you log out."
            fi
            systemctl --user daemon-reload || die "systemctl --user daemon-reload failed"
            systemctl --user enable --now "$SERVICE_NAME" || die "could not enable/start $SERVICE_NAME — try: systemctl --user status $SERVICE_NAME"
            START_CMD="systemctl --user restart $SERVICE_NAME"
            STOP_CMD="systemctl --user stop $SERVICE_NAME"
            SERVICE_STATUS_CMD="systemctl --user status $SERVICE_NAME --no-pager"
            LOG_HINT="journalctl --user -u $SERVICE_NAME -f"
            ok "postwisp installed as a user service."
        fi
    else
        # --- no systemd: offer to start by hand ---------------------------
        MANUAL_MODE=1
    fi
fi

if [ "$MANUAL_MODE" = 1 ]; then
    if [ -z "$SERVICE_STATUS_CMD" ]; then
        step "3/7 Start the server"
        echo "No service (not needed to run locally — the non-Linux or"
        echo "no-systemd case also lands here), so the server is started"
        echo "by hand. It stores everything in"
        echo "./${DATA_DIR}/ and, on first boot, prints a one-time setup URL"
        echo "with a token."
        START="$(ask "Start it in the background now? Press Enter for yes, or type 'no' to start it yourself:")"
        mkdir -p "$DATA_DIR"
        if [ "$START" != "no" ]; then
            if [ -f "$DATA_DIR/postwisp.pid" ] && kill -0 "$(cat "$DATA_DIR/postwisp.pid")" 2>/dev/null; then
                ok "Already running (pid $(cat "$DATA_DIR/postwisp.pid"))."
            else
                nohup "$BIN" >> "$DATA_DIR/server.log" 2>&1 &
                echo $! > "$DATA_DIR/postwisp.pid"
                ok "Started in the background (pid $(cat "$DATA_DIR/postwisp.pid"), log: $DATA_DIR/server.log)."
            fi
        else
            echo "Start it yourself in another terminal:  $BIN"
        fi
        START_CMD="$BIN"
        STOP_CMD="kill \$(cat $DATA_DIR/postwisp.pid)"
        SERVICE_STATUS_CMD="kill -0 \$(cat $DATA_DIR/postwisp.pid) && echo running"
        LOG_HINT="tail -f $DATA_DIR/server.log"
    fi
fi

# ---------------------------------------------------------------- 4/7 ---
step "4/7 Confirm it is running"
echo "Waiting for the server to answer $BASE_URL/status (up to 30s)..."
UP=0
for _ in $(seq 1 30); do
    if curl -sf "$BASE_URL/status" >/dev/null 2>&1; then UP=1; break; fi
    sleep 1
done
if [ "$UP" = 1 ]; then
    ok "server is running — $BASE_URL/status says: $(curl -sf "$BASE_URL/status")"
else
    echo "The server did not answer. Service status / recent log:"
    if [ -n "$SERVICE_STATUS_CMD" ]; then
        eval "$SERVICE_STATUS_CMD" 2>&1 | head -30 || true
    fi
    [ -f "$DATA_DIR/server.log" ] && tail -n 20 "$DATA_DIR/server.log" || true
    die "no server on $BASE_URL. Check the status above; then rerun this script."
fi

# ---------------------------------------------------------------- 5/7 ---
rm -f "$JAR"
TOKEN="$(ask "Paste the setup token from the server's console ($LOG_HINT), or press Enter if the database is already initialized:")"
if [ -n "$TOKEN" ]; then
    ok "Setup token captured: $TOKEN"
fi

step "5/7 Create the admin account"
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

step "6/7 Log in"
RESP="$(curl -s -w '\n%{http_code}' -c "$JAR" -X POST "$BASE_URL/api/login" \
    -H 'Content-Type: application/json' \
    -d "{\"username\":\"$(json "$USERNAME")\",\"password\":\"$(json "$PASSWORD")\"}")"
CODE="$(echo "$RESP" | tail -n1)"
[ "$CODE" = "200" ] || die "login rejected (HTTP $CODE): $(echo "$RESP" | head -n1)"
ok "Logged in; session cookie saved to $JAR."
curl -sf -b "$JAR" "$BASE_URL/api/me" >/dev/null || die "session check failed (/api/me)."

step "7/7 Choose the site theme"
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

echo
echo "Unsplash access key (optional)"
echo "The editor's image search and cover-photo picker use the Unsplash API."
echo "A free Access Key comes from creating an app at"
echo "  https://unsplash.com/oauth/applications  (demo tier: 50 requests/hour)."
UKEY="$(ask "Paste your Unsplash Access Key (or press Enter to skip):")"
if [ -n "$UKEY" ]; then
    # The key rides in ./env — read by the server itself on every boot, so
    # the editor picks it up automatically and the author is never asked
    # for it in the browser. Also pushed to the server settings below, so
    # both paths agree from the first login.
    printf '# postwisp environment — read by the server at boot.\n# See README-env.md in this directory.\nPW_UNSPLASH_KEY=%s\n' "$UKEY" > env
    chmod 600 env
    RESP="$(curl -s -w '\n%{http_code}' -b "$JAR" -X PUT "$BASE_URL/api/settings" \
        -H 'Content-Type: application/json' \
        -d "{\"unsplash_key\":\"$(json "$UKEY")\"}")"
    CODE="$(echo "$RESP" | tail -n1)"
    [ "$CODE" = "200" ] || die "Unsplash key save rejected (HTTP $CODE): $(echo "$RESP" | head -n1)"
    ok "Unsplash key saved to ./env (server settings updated too)."
else
    echo "Skipped — you can add one later: put PW_UNSPLASH_KEY=... in ./env"
    echo "(see README-env.md) or use the Settings page ($BASE_URL/settings)."
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
echo "Your blog (the server keeps running in the background):"
echo "  Home:             $BASE_URL/"
echo "  All posts:        $BASE_URL/posts  (?tag=NAME lists one tag)"
echo "  About:            $BASE_URL/about"
echo "  Dashboard:        $BASE_URL/dashboard"
echo
echo "Handy commands:"
if [ -n "$START_CMD" ]; then
    echo "  Check it is up:   curl $BASE_URL/status   (should say: postwisp ok)"
    [ "$SERVICE_STATUS_CMD" != "kill -0 \$(cat $DATA_DIR/postwisp.pid) && echo running" ] && \
        echo "  Service status:   $SERVICE_STATUS_CMD"
    echo "  Restart:          $START_CMD"
    echo "  Stop:             $STOP_CMD"
    echo "  Logs:             $LOG_HINT"
fi
echo "  Data lives in:    $APP_DIR/$DATA_DIR/"
echo
echo "Last step: edit the templates in ./templates/ as you see fit — the"
echo "server reads them from disk, so changes show up on the next page"
echo "load, no restart needed."
