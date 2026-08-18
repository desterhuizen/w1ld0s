#!/usr/bin/env bash
# lib/common.sh — shared helpers for the w1ld0s provisioner.
# `source` this from bootstrap.sh / modules; do NOT execute it directly.
#
# Design rules this file enforces:
#   * run as the normal user; sudo is called explicitly where root is needed
#   * apt is for native/system packages only
#   * every Python CLI tool goes in its own pipx venv (pipx_tool)
#   * toolkits needing patched deps get a dedicated venv (venv_create)
#   * everything is idempotent — safe to re-run

# ---- paths -----------------------------------------------------------------
# W1LD0S_ROOT is the repo root; resolved by bootstrap.sh, falls back here.
W1LD0S_ROOT="${W1LD0S_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
export W1LD0S_ROOT

OPT_DIR="${OPT_DIR:-/opt/w1ld0s}"        # user-owned tree: venvs, ghidra, burp, wordlists
VENV_DIR="${VENV_DIR:-$OPT_DIR/venvs}"   # dedicated (non-pipx) python venvs
TOOLS_DIR="${TOOLS_DIR:-$OPT_DIR/tools}" # cloned tools that aren't personal repos
WORDLISTS_DIR="${WORDLISTS_DIR:-$OPT_DIR/wordlists}"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"   # PATH shim target
REPOS_DIR="${REPOS_DIR:-$HOME/tools/repos}"       # personal + third-party repos (alias-compatible)
BINARIES_DIR="${BINARIES_DIR:-$HOME/tools/binaries}"  # prebuilt binaries (alias-compatible)
export OPT_DIR VENV_DIR TOOLS_DIR WORDLISTS_DIR BIN_DIR REPOS_DIR BINARIES_DIR

# ---- PATH ------------------------------------------------------------------
# Every module gets the full toolchain PATH here, not from whichever module
# happened to export it first. Modules used to inherit go/cargo/BIN_DIR only
# because 00-base ran earlier in the SAME shell, so running a module on its own
# ("./bootstrap.sh 20") silently built without them — that is how netexec ended
# up failing with "can't find Rust compiler" while rustup was installed all along.
for _p in "$BIN_DIR" /usr/local/go/bin "$HOME/go/bin" "$HOME/.cargo/bin"; do
  case ":$PATH:" in *":$_p:"*) ;; *) PATH="$_p:$PATH" ;; esac
done
unset _p
export PATH

# ---- logging ---------------------------------------------------------------
# ALL log output goes to stderr, deliberately. Helpers like venv_create return
# their result on stdout via command substitution; a single log line on stdout
# gets captured into the caller's variable and silently corrupts the path.
# Run the provisioner with 2>&1 to capture a full log (see README).
log()  { printf '\033[1;34m[*]\033[0m %s\n' "$*" >&2; }
ok()   { printf '\033[1;32m[+]\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[-]\033[0m %s\n' "$*" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

# Strip leading/trailing whitespace. List files align columns with runs of
# spaces, so a single "${x# }" is not enough.
_trim() { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; printf '%s' "${s%"${s##*[![:space:]]}"}"; }

# ---- host arch -------------------------------------------------------------
# Release assets spell the arch two ways; expose both. Used by gh_release to
# expand @ARCH@ / @ARCH_ALT@ in tools.d/releases.gh globs.
case "$(uname -m)" in
  x86_64)  W1LD0S_ARCH=x86_64;  W1LD0S_ARCH_ALT=amd64 ;;
  aarch64) W1LD0S_ARCH=aarch64; W1LD0S_ARCH_ALT=arm64 ;;
  *)       W1LD0S_ARCH="$(uname -m)"; W1LD0S_ARCH_ALT="$W1LD0S_ARCH" ;;
esac
export W1LD0S_ARCH W1LD0S_ARCH_ALT

# ---- guards ----------------------------------------------------------------
[ "$(id -u)" -ne 0 ] || die "Run as your normal user, not root. Modules call sudo where needed."
have sudo || die "sudo is required."

# ---- health checks ---------------------------------------------------------
# These encode repairs we previously had to do by hand, so a fresh box never
# needs them and a damaged box says so instead of failing obscurely later.

# i386 enabled on a non-x86_64 host is the state that let apt evict the native
# compiler. We do NOT purge automatically — dropping an architecture takes
# ~200 packages with it, which is the operator's call — but we say exactly how.
check_foreign_i386() {
  [ "$W1LD0S_ARCH" = "x86_64" ] && return 0
  dpkg --print-foreign-architectures 2>/dev/null | grep -qx i386 || return 0
  warn "i386 architecture is enabled on $W1LD0S_ARCH — apt can resolve multilib"
  warn "  packages to :i386 builds and displace the native toolchain. Clean up with:"
  warn "    sudo apt-get purge -y '?architecture(i386)'"
  warn "    sudo apt-get autoremove --purge -y"
  warn "    sudo dpkg --remove-architecture i386 && sudo apt-get update"
  return 1
}

# A missing cc surfaces much later as a baffling wheel-build error, so check it
# up front and self-repair if we can.
check_toolchain() {
  if ! have cc || ! have gcc; then
    warn "no C compiler on PATH — source builds (lxml, pycurl, hcxtools, …) will fail"
    log "restoring build-essential…"
    apt_install build-essential || true
    have cc || { warn "still no cc — fix with: sudo apt-get install -y build-essential"; return 1; }
    ok "C toolchain restored"
  fi
  # Rust is needed by NetExec's aardwolf dependency; rustup installs to ~/.cargo.
  have cargo || warn "cargo not on PATH — NetExec and other Rust-backed wheels will fail to build"
  return 0
}

# On non-Ubuntu we still allow running (fix-forward), but warn loudly.
if [ -r /etc/os-release ]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  case "${ID:-}" in
    ubuntu) : ;;
    debian) warn "Detected Debian, not Ubuntu — apt names mostly overlap; watch for misses." ;;
    kali)   warn "Detected Kali — w1ld0s targets Ubuntu; some 'de-Kali'd' choices are redundant here." ;;
    *)      warn "Untested distro '${ID:-unknown}'. Proceeding; expect to fix-forward." ;;
  esac
fi

# ---- apt -------------------------------------------------------------------
_APT_UPDATED=0
apt_refresh() { [ "$_APT_UPDATED" -eq 1 ] || { sudo apt-get update -qq && _APT_UPDATED=1; }; }
# --no-remove is a hard safety rule, not a tweak. Provisioning must never
# UNINSTALL anything: with i386 enabled, "apt-get install -y gcc-multilib" on
# arm64 happily resolves to gcc-multilib:i386 and rips out the native gcc/g++/
# build-essential to make room — exiting 0, so the script sees a clean install
# and every later source build dies on "cc: No such file or directory".
# With --no-remove apt refuses that plan and we warn instead.
_apt_one() {
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends --no-remove "$1"
}
# apt-get aborts the ENTIRE batch when one package is unavailable, which used to
# silently gut whole modules (they still reported success). Try the batch first
# for speed, then fall back to one-by-one so we lose only the bad packages and
# name each one.
apt_install() {
  [ "$#" -gt 0 ] || return 0
  apt_refresh
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends --no-remove "$@" && return 0
  [ "$#" -gt 1 ] || { warn "apt: failed '$1'"; return 1; }
  warn "apt: batch of $# failed — retrying individually to isolate the bad package(s)"
  local p rc=0
  for p in "$@"; do
    _apt_one "$p" || { warn "apt: failed '$p' (continuing)"; rc=1; }
  done
  return "$rc"
}
# Install every non-comment entry from a tools.d/<name> apt list.
apt_install_list() {
  local pkgs; mapfile -t pkgs < <(read_list "$1")
  [ "${#pkgs[@]}" -gt 0 ] || { log "apt list $1 empty"; return 0; }
  log "apt: installing ${#pkgs[@]} packages from $1"
  apt_install "${pkgs[@]}"
}

# ---- older interpreters (on demand only) -----------------------------------
# The system Python is the right default and stays the default. A few tools are
# pinned below the system version; ensure_python fetches just that interpreter.
# deadsnakes is only added to the box if a list actually asks for it — we do not
# carry a third-party PPA for nothing.
ensure_python() {  # ensure_python <x.y>
  local v="$1"
  have "python$v" && return 0
  log "python$v not installed — enabling deadsnakes PPA to fetch it"
  apt_install software-properties-common || return 1
  sudo add-apt-repository -y ppa:deadsnakes/ppa >/dev/null 2>&1 \
    || { warn "deadsnakes PPA add failed (no build for this release?)"; return 1; }
  _APT_UPDATED=0
  apt_install "python$v" "python$v-venv" "python$v-dev" || return 1
  have "python$v"
}

# ---- pipx (one isolated venv per CLI tool) ---------------------------------
pipx_tool() {  # pipx_tool <name> [pip-spec] [python-x.y]
  local name="$1" spec="${2:-$1}" pyver="${3:-}"
  # A pinned one-field line arrives here as "impacket==0.13.1", but `pipx list`
  # reports the bare package name — so the presence check below would never
  # match, and every re-run would try to reinstall an already-installed tool.
  # Strip any version specifier or extras before comparing.
  name="${name%%[<>=\[]*}"
  local -a extra=()
  if [ -n "$pyver" ]; then
    ensure_python "$pyver" || { warn "pipx: python$pyver unavailable; skipping $name"; return 1; }
    extra=(--python "python$pyver")
  fi
  if pipx list 2>/dev/null | grep -qiE "package $name "; then
    log "pipx: $name present (upgrade later with: pipx upgrade $name)"
  else
    log "pipx: install $spec${pyver:+ (on python$pyver)}"
    pipx install "${extra[@]}" "$spec" || warn "pipx: failed to install $spec"
  fi
}
# Install every entry from a tools.d/<name>.pipx list. Line format:
#   name                          -> pipx install name
#   name  <pip-spec>              -> pipx install <pip-spec>   (git+ URLs, extras, ==pins)
#   name  --python X.Y [pip-spec] -> same, but in a python X.Y venv
# The --python directive lives in the list so every interpreter exception is
# visible where the tool is declared, rather than as a hidden global default.
pipx_install_list() {
  local line name spec pyver
  while IFS= read -r line; do
    name="${line%% *}"; spec="${line#"$name"}"
    pyver=""
    if [[ "$spec" =~ (^|[[:space:]])--python[=[:space:]]+([0-9]+\.[0-9]+)([[:space:]]|$) ]]; then
      pyver="${BASH_REMATCH[2]}"
      spec="${spec/"${BASH_REMATCH[0]}"/ }"
    fi
    spec="$(_trim "$spec")"
    [ -n "$spec" ] || spec="$name"
    pipx_tool "$name" "$spec" "$pyver"
  done < <(read_list "$1")
}

# ---- dedicated venvs (toolkits needing pinned/patched deps) -----------------
venv_create() {  # venv_create <name> [pip-specs...] ; echoes the venv path
  local name="$1"; shift || true
  local path="$VENV_DIR/$name"
  if [ ! -d "$path" ]; then
    log "venv: create $name"
    mkdir -p "$VENV_DIR"
    python3 -m venv "$path"
    "$path/bin/pip" install -q --upgrade pip wheel
  fi
  [ "$#" -eq 0 ] || "$path/bin/pip" install -q "$@"
  printf '%s\n' "$path"
}

# ---- go / cargo tool lists -------------------------------------------------
go_install_list() {  # each line: full go module path (with @version)
  have go || { warn "go not installed; skipping $1"; return 0; }
  local mod
  while IFS= read -r mod; do
    log "go install $mod"
    go install "$mod" || warn "go: failed $mod"
  done < <(read_list "$1")
}

# ---- GitHub release helper -------------------------------------------------
# gh_release <owner/repo[@tag]> <asset-glob> <dest-file>
# With no @tag it takes the latest release; with one it takes that exact release,
# which is how releases.gh pins. Pin the TAG, never the resolved asset filename —
# the filename carries the arch, and a pinned filename cannot be rebuilt on the
# other architecture.
# @ARCH@ / @ARCH_ALT@ in the glob expand to this host's arch (x86_64/aarch64 and
# amd64/arm64). Use them for tools that RUN here; leave target-payload binaries
# (pspy, PrintSpoofer, …) hardcoded — their arch is the victim's, not ours.
gh_release() {
  local spec="$1" glob="$2" dest="$3"
  local repo="${spec%@*}" tag=""
  [ "$spec" = "$repo" ] || tag="${spec##*@}"
  glob="${glob//@ARCH@/$W1LD0S_ARCH}"
  glob="${glob//@ARCH_ALT@/$W1LD0S_ARCH_ALT}"
  [ -e "$dest" ] && { log "have $(basename "$dest")"; return 0; }
  mkdir -p "$(dirname "$dest")"
  local api="https://api.github.com/repos/$repo/releases/latest"
  [ -z "$tag" ] || api="https://api.github.com/repos/$repo/releases/tags/$tag"
  local url
  url=$(curl -fsSL "$api" \
        | grep -oE '"browser_download_url": *"[^"]+"' | cut -d'"' -f4 \
        | grep -E "$glob" | head -n1)
  [ -n "$url" ] || { warn "gh_release: no asset matching '$glob' in $repo${tag:+ @ $tag}"; return 1; }
  log "gh_release: $repo${tag:+@$tag} -> $(basename "$dest")"
  curl -fsSL "$url" -o "$dest"
}

# ---- misc ------------------------------------------------------------------
shim() { mkdir -p "$BIN_DIR"; ln -sf "$2" "$BIN_DIR/$1"; ok "shim $1 -> $2"; }

clone_or_pull() {  # clone_or_pull <git-url> [dest-dir]
  local url="$1" dest="${2:-$REPOS_DIR/$(basename "$1" .git)}"
  if [ -d "$dest/.git" ]; then
    log "repo up-to-date check: $(basename "$dest")"
    git -C "$dest" pull --quiet --ff-only 2>/dev/null || warn "pull failed for $dest (local changes?)"
  else
    log "clone $url"
    git clone --quiet "$url" "$dest" || warn "clone failed: $url"
  fi
}

# Read a tools.d list file, stripping comments and blank lines.
read_list() {
  local f="$W1LD0S_ROOT/tools.d/$1"
  [ -f "$f" ] || die "missing list: $f"
  sed -e 's/#.*//' -e 's/[[:space:]]*$//' -e '/^[[:space:]]*$/d' "$f"
}

# Copy an imported asset (from assets/) to a destination, backing up any existing file once.
install_asset() {  # install_asset <assets/relpath> <dest>
  local src="$W1LD0S_ROOT/assets/$1" dest="$2"
  [ -e "$src" ] || { warn "asset missing: $1"; return 1; }
  mkdir -p "$(dirname "$dest")"
  if [ -e "$dest" ] && [ ! -L "$dest" ] && ! cmp -s "$src" "$dest" 2>/dev/null; then
    cp -a "$dest" "$dest.w1ld0s.bak" && warn "backed up existing $dest -> $dest.w1ld0s.bak"
  fi
  cp -a "$src" "$dest"
  ok "asset: $1 -> $dest"
}
