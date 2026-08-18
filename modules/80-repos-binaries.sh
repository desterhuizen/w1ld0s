#!/usr/bin/env bash
# 80-repos-binaries.sh — clone the third-party repo set and fetch prebuilt binaries.
[ -n "${W1LD0S_ROOT:-}" ] || { W1LD0S_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; source "$W1LD0S_ROOT/lib/common.sh"; }

# --- clone third-party repos into ~/tools/repos (alias-compatible paths) -----
# git@ URLs need your SSH key; https lines (hacktricks) work without it.
log "Cloning third-party repos into $REPOS_DIR…"
while IFS= read -r url; do
  clone_or_pull "$url" "$REPOS_DIR/$(basename "$url" .git)"
done < <(read_list repos.git)

# --- prebuilt privesc binaries via GitHub releases --------------------------
# Parse the 'linux/windows binary' rows of releases.gh: repo  asset-regex  dest
log "Fetching prebuilt binaries (pspy / PrintSpoofer / GodPotato)…"
while read -r repo glob dest; do
  case "$dest" in
    tools/binaries/*) gh_release "$repo" "$glob" "$HOME/$dest" || true ;;
  esac
done < <(read_list releases.gh)
chmod +x "$BINARIES_DIR"/pspy/pspy* 2>/dev/null || true

# --- putty + Sysinternals (handy on engagements) ----------------------------
if [ ! -d "$BINARIES_DIR/SysinternalsSuite" ]; then
  log "Fetching Sysinternals Suite…"
  curl -fsSL https://download.sysinternals.com/files/SysinternalsSuite.zip -o "$HOME/.local/tmp/sysinternals.zip" \
    && unzip -q -o "$HOME/.local/tmp/sysinternals.zip" -d "$BINARIES_DIR/SysinternalsSuite" || warn "sysinternals fetch failed"
fi
have putty || apt_install putty-tools

ok "repos + binaries staged in $REPOS_DIR and $BINARIES_DIR."
