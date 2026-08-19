#!/usr/bin/env bash
# 35-webserver.sh — nginx as a quiet static file host for /var/www/html.
#
# This is the box's payload/loot delivery server: `cp shell.exe /var/www/html`
# and the target fetches it. The whole point is that the response tells the
# target's blue team as little as possible about what served it, so:
#
#   * no Server header at all      (server_tokens off only removes the version;
#                                   headers-more deletes the header)
#   * no Date, no Last-Modified, no ETag  — no clock, no build times
#   * no stock welcome page, no directory listing, no nginx error pages
#   * anything that is not a real file is a bodyless 404, including 403s
#
# The config lives in assets/nginx/w1ld0s.conf; this module installs it, unhooks
# the distro default site, and refuses to touch the running service unless
# `nginx -t` accepts the result. Re-runnable.
[ -n "${W1LD0S_ROOT:-}" ] || { W1LD0S_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; source "$W1LD0S_ROOT/lib/common.sh"; }

apt_install_list webserver.apt

# apt_install carries --no-remove, so a pre-existing apache2 is never displaced
# — it just loses the race for :80 at boot and nginx silently fails to start.
# Say so rather than uninstalling it, which is the operator's call.
if dpkg -s apache2 >/dev/null 2>&1; then
  warn "apache2 is installed and also binds :80 — nginx will fail to start while it runs."
  warn "  stop it with: sudo systemctl disable --now apache2"
fi

SITE_SRC="$W1LD0S_ROOT/assets/nginx/w1ld0s.conf"
SITE_AVAIL=/etc/nginx/sites-available/w1ld0s
SITE_ENABLED=/etc/nginx/sites-enabled/w1ld0s
WEBROOT=/var/www/html

# nginx lives in /usr/sbin, which is not on a normal user's PATH, so `have
# nginx` says no on a box where it is installed — the same trap that made
# module 06 take the fallback path for plymouth-set-default-theme. Test the
# binary, not the PATH lookup. (sudo's secure_path does include /usr/sbin, so
# `sudo nginx -t` below is fine.)
NGINX_BIN="$(command -v nginx 2>/dev/null || echo /usr/sbin/nginx)"
if [ ! -x "$NGINX_BIN" ]; then
  warn "nginx did not install — skipping the web server config"
elif [ ! -f "$SITE_SRC" ]; then
  warn "missing $SITE_SRC — skipping the web server config"
else
  # --- the blank error body -------------------------------------------------
  # The site config points every error status at this file. It must exist and
  # be empty: `return 404 ''` cannot produce an empty body (nginx ignores an
  # empty text argument and serves its stock page instead), so the only way to
  # get a truly bodyless error is to serve a zero-byte file. Kept outside
  # $WEBROOT so it can never be listed or fetched directly.
  BLANK_DIR=/usr/share/nginx/w1ld0s
  sudo mkdir -p "$BLANK_DIR"
  if [ ! -f "$BLANK_DIR/_blank" ] || [ -s "$BLANK_DIR/_blank" ]; then
    sudo truncate -s 0 "$BLANK_DIR/_blank" 2>/dev/null \
      || sudo sh -c ": > '$BLANK_DIR/_blank'" \
      || warn "could not create $BLANK_DIR/_blank — errors will serve the stock page"
    sudo chmod 644 "$BLANK_DIR/_blank" 2>/dev/null || true
  fi

  # --- build the site config ------------------------------------------------
  # The headers-more directives are dropped when the module is not loadable.
  # The test is the load-time drop-in, not `dpkg -s`: it is the file nginx
  # actually reads, and a dynamic module does not show up in `nginx -V` either.
  # Getting this wrong is not cosmetic — an unknown more_clear_headers is fatal
  # at startup, so this module's config would take the whole service down.
  SITE_TMP="$(mktemp)"
  if [ -e /etc/nginx/modules-enabled/50-mod-http-headers-more-filter.conf ]; then
    cp "$SITE_SRC" "$SITE_TMP"
  else
    warn "headers-more module not present — Server: nginx will be sent"
    warn "  install it with: sudo apt-get install libnginx-mod-http-headers-more-filter"
    sed '/# needs headers-more$/d' "$SITE_SRC" > "$SITE_TMP"
  fi

  if [ -f "$SITE_AVAIL" ] && ! cmp -s "$SITE_TMP" "$SITE_AVAIL"; then
    sudo cp -a "$SITE_AVAIL" "$SITE_AVAIL.w1ld0s.bak" \
      && warn "backed up $SITE_AVAIL -> $SITE_AVAIL.w1ld0s.bak"
  fi
  sudo install -D -m644 "$SITE_TMP" "$SITE_AVAIL"
  rm -f "$SITE_TMP"
  sudo ln -sfn "$SITE_AVAIL" "$SITE_ENABLED"

  # --- default site and default pages ---------------------------------------
  # The stock site is what serves the "Welcome to nginx!" page, and it also
  # claims default_server on :80 — leaving it enabled is a config error, not
  # just a cosmetic one.
  if [ -e /etc/nginx/sites-enabled/default ]; then
    sudo rm -f /etc/nginx/sites-enabled/default
    log "unhooked the default nginx site"
  fi

  sudo mkdir -p "$WEBROOT"
  sudo rm -f "$WEBROOT/index.nginx-debian.html"
  # index.html is only removed when it IS a stock page. A hand-written landing
  # page (a phishing clone, a file index) lives at exactly this path, and this
  # module must never eat it.
  if [ -f "$WEBROOT/index.html" ]; then
    INDEX_HEAD="$(head -c 4096 "$WEBROOT/index.html" 2>/dev/null)"
    case "$INDEX_HEAD" in
      *"Welcome to nginx"*|*"Apache2 Ubuntu Default Page"*|*"Apache2 Debian Default Page"*)
        sudo rm -f "$WEBROOT/index.html"; log "removed the stock default index.html" ;;
      *)
        log "keeping $WEBROOT/index.html (not a stock default page)" ;;
    esac
  fi

  # Own the webroot so dropping payloads never needs sudo — same reasoning as
  # OPT_DIR being user-owned. nginx reads as www-data; 0755 dirs / 0644 files
  # are enough for that.
  sudo chown -R "$(id -un):$(id -gn)" "$WEBROOT"

  # --- validate before touching the service ---------------------------------
  # `nginx -t` is the only thing between a typo here and a box with no web
  # server. On failure the site is unhooked again so a reload elsewhere (a
  # package upgrade, a reboot) cannot pick up the broken file.
  NGINX_TEST="$(sudo nginx -t 2>&1)"
  if ! printf '%s\n' "$NGINX_TEST" | grep -q 'test is successful'; then
    warn "nginx rejected the config — unhooking our site and leaving the service alone:"
    printf '%s\n' "$NGINX_TEST" | sed 's/^/    /' >&2
    sudo rm -f "$SITE_ENABLED"
  else
    sudo systemctl enable --now nginx >/dev/null 2>&1 || warn "systemctl enable --now nginx failed"
    sudo systemctl reload nginx >/dev/null 2>&1 || sudo systemctl restart nginx >/dev/null 2>&1 \
      || warn "nginx would not reload or restart — check: systemctl status nginx"

    # --- prove it from the box, not from the log ----------------------------
    # Captured, not piped into a condition: under pipefail a failing curl would
    # be reported even when grep matched (see CLAUDE.md).
    HDRS="$(curl -sS -m 3 -D - -o /dev/null "http://127.0.0.1/" 2>/dev/null)"
    if [ -z "$HDRS" ]; then
      warn "nginx did not answer on 127.0.0.1:80 — check: systemctl status nginx"
    else
      log "response headers for / (an empty webroot answers 404 by design):"
      printf '%s\n' "$HDRS" | sed 's/^/    /' >&2
      LEAKY="$(printf '%s\n' "$HDRS" | grep -icE '^(server|date|last-modified|etag):')"
      if [ "$LEAKY" -eq 0 ]; then
        ok "no Server/Date/Last-Modified/ETag in the response"
      else
        warn "$LEAKY identifying header(s) still present — is headers-more loaded?"
      fi
    fi
    ok "nginx serving $WEBROOT on :80 (enabled at boot; stop with: sudo systemctl disable --now nginx)"
    cat <<'EOF'

  Drop files straight in (the webroot is yours, no sudo):
      cp shell.exe /var/www/html/ && curl -sI http://127.0.0.1/shell.exe

  What a client sees: Content-Type, Content-Length, Connection, Accept-Ranges.
  Anything that is not a real file — wrong path, POST, denied — is a bodyless
  404, so 403/404/500 are indistinguishable from outside.

  Access logs are kept deliberately (/var/log/nginx/access.log): they are the
  record of which target pulled which payload.
EOF
  fi
fi
ok "webserver module finished."
