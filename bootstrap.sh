#!/usr/bin/env bash
# bootstrap.sh — provision a clean Ubuntu 26.04 LTS box into the w1ld0s
# pentest workstation. Idempotent: safe to re-run. Run as your normal user.
#
#   ./bootstrap.sh              # run all modules in order
#   ./bootstrap.sh 20 30        # run only modules whose name starts 20 / 30
#   ./bootstrap.sh 20-ad-network
#
set -uo pipefail

W1LD0S_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export W1LD0S_ROOT
# shellcheck source=lib/common.sh
source "$W1LD0S_ROOT/lib/common.sh"

ALL_MODULES=(
  00-base
  05-desktop-i3
  06-boot-branding
  07-gnome-shell
  10-python-isolation
  20-ad-network
  30-web
  35-webserver
  40-cloud
  50-re-binary
  60-payload-dev
  70-wireless
  80-repos-binaries
  90-tools
  95-private
  99-secrets
)

# Resolve requested modules (prefix match) or default to all.
select_modules() {
  [ "$#" -eq 0 ] && { printf '%s\n' "${ALL_MODULES[@]}"; return; }
  local want m matched
  for want in "$@"; do
    matched=0
    for m in "${ALL_MODULES[@]}"; do
      [[ "$m" == "$want"* ]] && { printf '%s\n' "$m"; matched=1; }
    done
    [ "$matched" -eq 1 ] || warn "no module matches '$want'"
  done
}
mapfile -t MODULES < <(select_modules "$@")
[ "${#MODULES[@]}" -gt 0 ] || die "no modules selected"

log "Priming sudo (you may be prompted once)…"
sudo -v || die "sudo failed"
# keep the sudo timestamp warm for the whole run
( while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done ) 2>/dev/null &
SUDO_KEEPALIVE=$!
trap 'kill "$SUDO_KEEPALIVE" 2>/dev/null' EXIT

mkdir -p "$BIN_DIR"
# Ensure /opt/w1ld0s exists and is user-owned (needs sudo once).
if [ ! -d "$OPT_DIR" ]; then
  sudo mkdir -p "$OPT_DIR"
  sudo chown -R "$(id -un):$(id -gn)" "$OPT_DIR"
fi
mkdir -p "$VENV_DIR" "$TOOLS_DIR" "$WORDLISTS_DIR" "$REPOS_DIR" "$BINARIES_DIR"

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) warn "$BIN_DIR is not on PATH yet — module 00 adds it to ~/.zshrc; open a new shell after." ;;
esac

# Box-state checks before any module runs — a contaminated apt state affects
# every module, so flag it once here rather than 13 times in the failures.
check_foreign_i386 || warn "continuing, but expect source builds to be fragile until that is cleaned up"

log "Running modules: ${MODULES[*]}"
for m in "${MODULES[@]}"; do
  f="$W1LD0S_ROOT/modules/$m.sh"
  [ -f "$f" ] || { warn "module file missing: $f (skipping)"; continue; }
  printf '\n\033[1;36m==== module: %s ====\033[0m\n' "$m"
  # shellcheck disable=SC1090
  if source "$f"; then ok "module $m done"; else warn "module $m reported errors (continuing)"; fi
done

printf '\n'
ok "bootstrap complete."
log "Open a new shell (or 'hash -r'), verify tools, then snapshot the VM as 'clean-base'."
log "First build is unpinned; once green, freeze versions back into tools.d/ with"
log "  ./tests/freeze-pins.sh --diff   (see docs/README.md 'Updating a box')."
