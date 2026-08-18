#!/usr/bin/env bash
# 00-base.sh — native packages, language toolchains, pipx, oh-my-zsh, dotfiles, PATH.
# Sourced by bootstrap.sh (common.sh already loaded). Standalone-safe:
[ -n "${W1LD0S_ROOT:-}" ] || { W1LD0S_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; source "$W1LD0S_ROOT/lib/common.sh"; }

log "Installing base apt packages…"
apt_install_list base.apt

# Confirm the compiler actually survived the apt run before anything tries to
# build from source (this is the failure that cost us a whole rebuild cycle).
check_toolchain || warn "continuing without a working C toolchain — expect build failures"

# fd-find / bat ship as fdfind / batcat on Debian/Ubuntu — provide expected names.
have fdfind && ! have fd  && shim fd  "$(command -v fdfind)"
have batcat && ! have bat && shim bat "$(command -v batcat)"

# --- Go (Ubuntu's is often old; install latest to /usr/local/go) ------------
GO_VERSION="${GO_VERSION:-1.24.5}"
if ! have go || [[ "$(go version 2>/dev/null)" != *"go$GO_VERSION"* ]]; then
  arch="$(dpkg --print-architecture)"   # amd64 / arm64
  tgz="go${GO_VERSION}.linux-${arch}.tar.gz"
  log "Installing Go ${GO_VERSION} (${arch})…"
  curl -fsSL "https://go.dev/dl/${tgz}" -o "/tmp/$tgz" \
    && sudo rm -rf /usr/local/go \
    && sudo tar -C /usr/local -xzf "/tmp/$tgz" \
    && rm -f "/tmp/$tgz" || warn "Go install failed"
fi
export PATH="/usr/local/go/bin:$HOME/go/bin:$PATH"

# --- Rust (rustup, user-local) ----------------------------------------------
if ! have cargo; then
  log "Installing Rust (rustup)…"
  curl -fsSL https://sh.rustup.rs | sh -s -- -y --no-modify-path || warn "rustup failed"
fi
export PATH="$HOME/.cargo/bin:$PATH"

# --- pipx ready -------------------------------------------------------------
have pipx || apt_install pipx
pipx ensurepath >/dev/null 2>&1 || true

# --- oh-my-zsh (unattended) -------------------------------------------------
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  log "Installing oh-my-zsh…"
  RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended \
    || warn "oh-my-zsh install failed"
fi
# Make zsh the login shell (no-op if already). Plain `chsh` authenticates the
# calling user through PAM and prompts for a password, which a provisioning run
# cannot answer — it failed silently and left the account on bash, where none of
# the ~/.zshrc PATH work below applies (go/bin, gem bin, aliases all invisible).
# `sudo chsh -s <shell> <user>` skips that prompt; we already hold sudo here.
#
# The result is CHECKED against /etc/passwd, not against chsh's exit status:
# that is how the first build reported nothing useful and still came up on bash.
ZSH_BIN="$(command -v zsh)"
login_shell() { getent passwd "$(id -un)" | cut -d: -f7; }
if [ -z "$ZSH_BIN" ]; then
  warn "zsh is not installed — leaving the login shell alone"
elif [ "$(login_shell)" = "$ZSH_BIN" ]; then
  log "login shell is already $ZSH_BIN"
else
  grep -qxF "$ZSH_BIN" /etc/shells || printf '%s\n' "$ZSH_BIN" | sudo tee -a /etc/shells >/dev/null
  # usermod is the fallback: it edits /etc/passwd directly and does not care
  # about PAM at all, so it still works where a hardened chsh refuses.
  sudo chsh -s "$ZSH_BIN" "$(id -un)" >/dev/null 2>&1 \
    || sudo usermod -s "$ZSH_BIN" "$(id -un)" >/dev/null 2>&1 || true
  if [ "$(login_shell)" = "$ZSH_BIN" ]; then
    ok "login shell set to $ZSH_BIN (takes effect at next login)"
  else
    warn "login shell is still $(login_shell); run: sudo chsh -s $ZSH_BIN $(id -un)"
  fi
fi

# --- dotfiles: tmux (zshrc is wired below to source the repo aliases) --------
install_asset tmux.conf "$HOME/.tmux.conf"
# TPM for tmux plugins referenced by the imported tmux.conf
[ -d "$HOME/.tmux/plugins/tpm" ] || git clone --quiet https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm" || warn "tpm clone failed"

# --- PATH + env + colours + alias sourcing in ~/.zshrc (managed block) ------
# The block is REWRITTEN when it differs from the one below, not skipped on
# sight of the begin marker: a box provisioned by an older revision would
# otherwise keep that revision's block forever and never see anything added
# here. It is re-appended at the end of the file on purpose — it has to come
# after `source $ZSH/oh-my-zsh.sh` to override oh-my-zsh's own settings.
ZMARK_BEGIN="# >>> w1ld0s >>>"
ZMARK_END="# <<< w1ld0s <<<"
ZBLOCK="$(mktemp)"
cat > "$ZBLOCK" <<'EOF'
# >>> w1ld0s >>>
export EDITOR='nvim'
export VISUAL='nvim'
export ROCKYOU='/usr/share/wordlists/rockyou.txt'
export PATH="$HOME/.local/bin:$HOME/go/bin:/usr/local/go/bin:$HOME/.cargo/bin:$PATH"

# Colours: keep zsh looking exactly like bash does on this box.
# Ubuntu's stock ~/.bashrc builds LS_COLORS with `dircolors -b`, honouring
# ~/.dircolors if one exists. oh-my-zsh runs the same two commands but only
# when LS_COLORS is empty, so anything that exports it earlier (/etc/zsh/*,
# a display manager, an inherited environment) leaves zsh on a palette that
# silently disagrees with bash. Set it outright instead of relying on that.
if command -v dircolors >/dev/null 2>&1; then
  if [ -r "$HOME/.dircolors" ]; then
    eval "$(dircolors -b "$HOME/.dircolors")"
  else
    eval "$(dircolors -b)"
  fi
fi
# Bash's own colour aliases, as a floor for a box where oh-my-zsh failed to
# install. `alias ls` returns 0 when omz already defined one, so these never
# overwrite omz's richer versions (its grep alias also carries --exclude-dir).
alias ls    >/dev/null 2>&1 || alias ls='ls --color=auto'
alias grep  >/dev/null 2>&1 || alias grep='grep --color=auto'
alias fgrep >/dev/null 2>&1 || alias fgrep='fgrep --color=auto'
alias egrep >/dev/null 2>&1 || alias egrep='egrep --color=auto'
# zsh's completion menu is uncoloured by default. Feed it the same table so a
# filename is the same colour under `ls` and in a completion listing.
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}

# Toolkit aliases/functions (present after module 90 clones w1ld0s-tools).
# Guarded because module 00 runs first: on the very first bootstrap this file
# does not exist yet, and it must not break the shell in the meantime.
[ -f "$HOME/tools/repos/w1ld0s-tools/aliases" ] \
  && source "$HOME/tools/repos/w1ld0s-tools/aliases"
# <<< w1ld0s <<<
EOF

touch "$HOME/.zshrc"
if ! grep -qF "$ZMARK_BEGIN" "$HOME/.zshrc"; then
  log "Appending w1ld0s block to ~/.zshrc…"
  { printf '\n'; cat "$ZBLOCK"; } >> "$HOME/.zshrc"
elif diff -q <(sed -n "/^$ZMARK_BEGIN\$/,/^$ZMARK_END\$/p" "$HOME/.zshrc") "$ZBLOCK" >/dev/null 2>&1; then
  log "~/.zshrc w1ld0s block is current"
else
  log "Refreshing the w1ld0s block in ~/.zshrc…"
  sed -i "/^$ZMARK_BEGIN\$/,/^$ZMARK_END\$/d" "$HOME/.zshrc"
  { printf '\n'; cat "$ZBLOCK"; } >> "$HOME/.zshrc"
fi
rm -f "$ZBLOCK"

# --- wordlists --------------------------------------------------------------
# Ubuntu has no 'seclists'/'wordlists' packages (Kali-only), so pull SecLists
# from GitHub. Shallow clone: full history is several GB of no value to us.
if [ ! -d "$WORDLISTS_DIR/SecLists/.git" ]; then
  log "Cloning SecLists into $WORDLISTS_DIR (large, one-off)…"
  git clone --quiet --depth 1 https://github.com/danielmiessler/SecLists.git \
    "$WORDLISTS_DIR/SecLists" || warn "SecLists clone failed"
else
  log "SecLists present; updating…"
  git -C "$WORDLISTS_DIR/SecLists" pull --quiet --depth 1 --ff-only 2>/dev/null \
    || warn "SecLists update failed (continuing with the existing copy)"
fi

# SecLists ships rockyou compressed; expand once so it is usable directly.
ROCKYOU_SRC="$WORDLISTS_DIR/SecLists/Passwords/Leaked-Databases/rockyou.txt.tar.gz"
if [ -f "$ROCKYOU_SRC" ] && [ ! -f "$WORDLISTS_DIR/rockyou.txt" ]; then
  log "Extracting rockyou.txt…"
  tar -xzf "$ROCKYOU_SRC" -C "$WORDLISTS_DIR" || warn "rockyou extract failed"
fi

# Kali-compatible paths under /usr/share/wordlists so $ROCKYOU and every
# cheatsheet/blog command that hardcodes those paths keep working.
sudo mkdir -p /usr/share/wordlists
[ -d "$WORDLISTS_DIR/SecLists" ] && sudo ln -sfn "$WORDLISTS_DIR/SecLists" /usr/share/wordlists/seclists
[ -f "$WORDLISTS_DIR/rockyou.txt" ] && sudo ln -sfn "$WORDLISTS_DIR/rockyou.txt" /usr/share/wordlists/rockyou.txt
ok "wordlists: $WORDLISTS_DIR (linked into /usr/share/wordlists)"

ok "base module finished. Go: $(go version 2>/dev/null || echo 'n/a'); pipx: $(pipx --version 2>/dev/null || echo n/a)"
