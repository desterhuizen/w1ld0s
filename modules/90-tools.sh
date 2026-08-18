#!/usr/bin/env bash
# 90-tools.sh — the operator toolkit that sits on top of the provisioned OS.
# Clones w1ld0s-tools, recreates the ~/.local/bin symlinks, builds reverse_ssh,
# and seeds the target/attack state the aliases source at shell startup.
#
# Everything here works on a box with no SSH key and no GitHub account: the
# toolkit clones over https. An ed25519 key is still generated, because a
# pentest workstation needs one and reverse_ssh authorises it below — but
# nothing in this module requires the key to be registered anywhere.
[ -n "${W1LD0S_ROOT:-}" ] || { W1LD0S_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; source "$W1LD0S_ROOT/lib/common.sh"; }

TOOLS_REPO_DIR="$REPOS_DIR/w1ld0s-tools"

# --- SSH key: generated fresh on THIS box, never copied from another host ----
# One key per workstation. If the VM is ever lost or burned you revoke one key
# instead of rotating a key that lives on several machines.
SSH_KEY="$HOME/.ssh/id_ed25519"

if [ ! -f "$SSH_KEY" ]; then
  log "No SSH key on this workstation — generating a fresh ed25519 keypair."
  log "You'll be prompted for a passphrase; leave it empty only if you accept an unprotected key."
  mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
  # Comment is deliberately neutral: no username, no hostname, no internal domain.
  # ssh-keygen would otherwise default to user@host and publish that with the key.
  ssh-keygen -t ed25519 -a 100 -f "$SSH_KEY" -C "w1ld0s" || warn "ssh-keygen failed"
  chmod 600 "$SSH_KEY" 2>/dev/null
  chmod 644 "$SSH_KEY.pub" 2>/dev/null
  ok "generated $SSH_KEY"
else
  log "Existing SSH key found at $SSH_KEY — leaving it alone."
fi

# A private key restored by hand (or copied off a backup) often arrives without
# its .pub, and everything downstream reads the .pub, not the key: the "add this
# to GitHub" banner printed an empty block, `gh ssh-key add` had no file, and
# reverse_ssh's authorized_* files were never written — all without one error,
# because each step was guarded by `[ -f "$SSH_KEY.pub" ]`. Derive it instead.
if [ -f "$SSH_KEY" ] && [ ! -f "$SSH_KEY.pub" ]; then
  log "No public half next to $SSH_KEY — deriving it from the private key…"
  ssh-keygen -y -f "$SSH_KEY" > "$SSH_KEY.pub" 2>/dev/null \
    && { chmod 644 "$SSH_KEY.pub"; ok "wrote $SSH_KEY.pub"; } \
    || { rm -f "$SSH_KEY.pub"; warn "could not derive the public key (passphrase-protected? run: ssh-keygen -y -f $SSH_KEY > $SSH_KEY.pub)"; }
fi

# --- the toolkit ------------------------------------------------------------
# $W1LD0S_TOOLS_REPO wins over the manifest so a fork can be pointed at without
# editing a tracked file.
# read_list resolves names against tools.d/ itself, and die()s on a missing
# file — guard so a deleted manifest degrades to a warning, not a dead bootstrap.
if [ -n "${W1LD0S_TOOLS_REPO:-}" ]; then
  TOOLS_REPO="$W1LD0S_TOOLS_REPO"
elif [ -f "$W1LD0S_ROOT/tools.d/tools.git" ]; then
  TOOLS_REPO="$(read_list tools.git | head -1)"
else
  TOOLS_REPO=""
fi
if [ -n "$TOOLS_REPO" ]; then
  clone_or_pull "$TOOLS_REPO" "$TOOLS_REPO_DIR"
else
  warn "no toolkit repo configured (tools.d/tools.git is empty) — skipping."
fi

# --- recreate the ~/.local/bin symlinks -------------------------------------
# setup_links resolves targets relative to $PWD, so it has to run from inside
# the checkout: a symlink farm built from anywhere else points nowhere.
if [ -x "$TOOLS_REPO_DIR/setup_links" ]; then
  log "Running setup_links…"
  ( cd "$TOOLS_REPO_DIR" && ./setup_links ) || warn "setup_links failed"
else
  warn "setup_links not found in $TOOLS_REPO_DIR — recreate ~/.local/bin symlinks manually."
fi

# --- build reverse_ssh + authorize this box's key ---------------------------
export PATH="/usr/local/go/bin:$HOME/go/bin:$PATH"
RSSH="$REPOS_DIR/reverse_ssh"   # cloned by module 80
if [ -d "$RSSH" ] && have go; then
  log "Building reverse_ssh (server + release)…"
  ( cd "$RSSH" && make server && make release ) || warn "reverse_ssh build failed"
  if [ -f "$SSH_KEY.pub" ]; then
    for f in authorized_controllee_keys authorized_keys; do
      touch "$RSSH/bin/$f"
      grep -qxf "$SSH_KEY.pub" "$RSSH/bin/$f" 2>/dev/null \
        || cat "$SSH_KEY.pub" >> "$RSSH/bin/$f"
    done
    ok "reverse_ssh authorized with this box's ed25519 pubkey"
  fi
fi

# --- seed target/attack state (aliases source these at shell startup) -------
[ -x "$BIN_DIR/target" ] && ( "$BIN_DIR/target" >/dev/null 2>&1 || true )
[ -x "$BIN_DIR/attack" ] && ( "$BIN_DIR/attack" >/dev/null 2>&1 || true )

# --- create workspace scaffolding dirs the aliases expect -------------------
mkdir -p "$HOME/smbshare" "$HOME/www" 2>/dev/null || true

ok "toolkit wired. Open a new zsh to load the aliases (\$IP, htricks, ysorerial, …)."
