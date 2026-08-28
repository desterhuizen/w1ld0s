#!/usr/bin/env bash
# 80-repos-binaries.sh — clone the third-party repo set, build the two tools that
# ship as source (ligolo-ng, searchsploit) and fetch prebuilt binaries.
[ -n "${W1LD0S_ROOT:-}" ] || { W1LD0S_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; source "$W1LD0S_ROOT/lib/common.sh"; }

# --- clone third-party repos into ~/tools/repos (alias-compatible paths) -----
# git@ URLs need your SSH key; https lines (hacktricks) work without it.
log "Cloning third-party repos into $REPOS_DIR…"
while IFS= read -r url; do
  clone_or_pull "$url" "$REPOS_DIR/$(basename "$url" .git)"
done < <(read_list repos.git)

# --- ligolo-ng: build the proxy and the agents from the clone ---------------
# NOT `make release`: that target is `goreleaser release --config
# .github/goreleaser.yml`, which wants goreleaser installed, a clean tag, and a
# GitHub token to publish with — none of which exist on a provisioning box.
# `make all` is the same compiler invocations without the publishing: proxy AND
# agent for linux and windows on both arches, into dist/. The cross-built set is
# worth the extra minute because the agent is the half you drop on the target,
# and its arch is the target's, not ours.
LIGOLO_DIR="$REPOS_DIR/ligolo-ng"
LIGOLO_PROXY="$LIGOLO_DIR/dist/ligolo-ng-proxy-linux_$W1LD0S_ARCH_ALT"
# `all` is four sub-targets and `linux` runs first, so the proxy above lands as
# soon as that one finishes. Guarding the rebuild on it alone would make a
# half-finished build permanent: the module logs "already built" from then on,
# and module 85 warns "nothing matches" for the agent rows in webroot.copy on
# every run. These are the artifacts that manifest expects — check all of them.
LIGOLO_ARTIFACTS=(
  "$LIGOLO_PROXY"
  "$LIGOLO_DIR/dist/ligolo-ng-agent-linux_amd64"
  "$LIGOLO_DIR/dist/ligolo-ng-agent-linux_arm64"
  "$LIGOLO_DIR/dist/ligolo-ng-agent-windows_amd64.exe"
  "$LIGOLO_DIR/dist/ligolo-ng-agent-windows_arm64.exe"
)
ligolo_built() {
  local f
  for f in "${LIGOLO_ARTIFACTS[@]}"; do [ -e "$f" ] || return 1; done
}
if [ ! -d "$LIGOLO_DIR" ]; then
  warn "ligolo-ng not cloned — check the clone above; skipping the build"
elif ! have go; then
  warn "go not on PATH — skipping the ligolo-ng build (run module 00 first)"
else
  if ligolo_built; then
    log "ligolo-ng already built (${#LIGOLO_ARTIFACTS[@]} artifacts in dist/)"
  else
    log "Building ligolo-ng (make all — proxy + agent, linux/windows, both arches)…"
    ( cd "$LIGOLO_DIR" && make all ) || warn "ligolo-ng build failed"
  fi
fi
if [ -x "$LIGOLO_PROXY" ]; then
  shim ligolo-proxy "$LIGOLO_PROXY"
  # The proxy creates a tun interface, so it always runs under sudo — and sudo's
  # secure_path does not include ~/.local/bin, so the shim alone leaves the
  # toolkit's `ligolo-start` alias reporting "command not found". Same fix as
  # module 30 gives Burp: a second name on the system PATH.
  if [ "$(readlink -f /usr/local/bin/ligolo-proxy 2>/dev/null)" = "$LIGOLO_PROXY" ]; then
    log "/usr/local/bin/ligolo-proxy already points at $LIGOLO_PROXY"
  elif sudo ln -sfn "$LIGOLO_PROXY" /usr/local/bin/ligolo-proxy; then
    ok "ligolo-proxy -> $LIGOLO_PROXY (system-wide, reachable under sudo)"
  else
    warn "could not link /usr/local/bin/ligolo-proxy — 'sudo ligolo-proxy' will not resolve"
  fi
fi

# --- exploitdb / searchsploit -----------------------------------------------
EXPLOITDB_DIR="$REPOS_DIR/exploitdb"
if [ ! -x "$EXPLOITDB_DIR/searchsploit" ]; then
  warn "no searchsploit in $EXPLOITDB_DIR — check the exploitdb clone above"
else
  # A plain symlink works: searchsploit locates its CSVs through
  # `dirname "$(readlink "$0")"`, which resolves one level of symlink back into
  # the checkout — the same reason the sqlmap and whatweb shims in module 30 do.
  shim searchsploit "$EXPLOITDB_DIR/searchsploit"
  # Without an rc file it takes that fallback and prints an "[i] Found (#2) …"
  # nag to stderr on every single search. Upstream's shipped .searchsploit_rc
  # hardcodes /opt/exploitdb, so write one that names this checkout instead.
  # The papers stanza is dropped: exploitdb-papers is a separate repo we do not
  # clone, and a path_array entry pointing at nothing is another nag.
  SEARCHSPLOIT_RC="$HOME/.searchsploit_rc"
  if [ ! -f "$SEARCHSPLOIT_RC" ]; then
    sed "s#@EXPLOITDB@#$EXPLOITDB_DIR#g" > "$SEARCHSPLOIT_RC" <<'EOF'
##-- Written by w1ld0s modules/80-repos-binaries.sh

##-- Program Settings
progname="$( basename "$0" )"


##-- Exploits
files_array+=("files_exploits.csv")
path_array+=("@EXPLOITDB@")
name_array+=("Exploit")
git_array+=("https://gitlab.com/exploit-database/exploitdb.git")
package_array+=("exploitdb")


##-- Shellcodes
files_array+=("files_shellcodes.csv")
path_array+=("@EXPLOITDB@")
name_array+=("Shellcode")
git_array+=("https://gitlab.com/exploit-database/exploitdb.git")
package_array+=("exploitdb")
EOF
    ok "wrote $SEARCHSPLOIT_RC pointing at $EXPLOITDB_DIR"
  elif grep -q "$EXPLOITDB_DIR" "$SEARCHSPLOIT_RC"; then
    log "$SEARCHSPLOIT_RC already points at $EXPLOITDB_DIR"
  else
    warn "$SEARCHSPLOIT_RC exists and does not name $EXPLOITDB_DIR — leaving it alone"
  fi
fi

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
