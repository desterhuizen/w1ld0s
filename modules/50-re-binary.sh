#!/usr/bin/env bash
# 50-re-binary.sh — Reverse-engineering / binary / mobile toolkit.
[ -n "${W1LD0S_ROOT:-}" ] || { W1LD0S_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; source "$W1LD0S_ROOT/lib/common.sh"; }

# --- native RE packages -----------------------------------------------------
# edb-debugger dropped: gone from the Ubuntu 26.04 archive (it was the only
# package in this batch that ever failed). gdb+pwndbg below covers the ground.
apt_install gdb radare2 binwalk checksec ltrace strace patchelf

# --- pwndbg (gdb enhancement) -----------------------------------------------
# pwndbg's setup.sh installs its deps with uv and EXITS 0 when uv is missing, so
# `|| warn` never fired and gdb was left sourcing a half-installed gdbinit.py.
# Install uv first, then confirm pwndbg actually loads instead of trusting $?.
if [ ! -d "$TOOLS_DIR/pwndbg" ]; then
  clone_or_pull https://github.com/pwndbg/pwndbg.git "$TOOLS_DIR/pwndbg"
  have uv || curl -fsSL https://astral.sh/uv/install.sh | sh >/dev/null 2>&1 || warn "uv install failed"
  ( cd "$TOOLS_DIR/pwndbg" && ./setup.sh ) || warn "pwndbg setup failed"
  gdb --batch -ex quit >/dev/null 2>&1 || warn "pwndbg did not load cleanly under gdb — check 'gdb --batch -ex quit'"
fi

# --- pipx RE tools ----------------------------------------------------------
log "Installing RE pipx tools…"
pipx_install_list re.pipx

# --- ghidra (release) -------------------------------------------------------
if [ ! -d "$OPT_DIR/ghidra" ]; then
  log "Installing Ghidra…"
  if gh_release NationalSecurityAgency/ghidra@Ghidra_12.1.2_build 'ghidra_.*_PUBLIC_.*\.zip$' "$HOME/.local/tmp/ghidra.zip"; then
    unzip -q -o "$HOME/.local/tmp/ghidra.zip" -d "$OPT_DIR"
    gdir="$(find "$OPT_DIR" -maxdepth 1 -type d -name 'ghidra_*_PUBLIC' | head -n1)"
    [ -n "$gdir" ] && { ln -sfn "$gdir" "$OPT_DIR/ghidra"; shim ghidra "$OPT_DIR/ghidra/ghidraRun"; }
  fi
fi

# --- mobile: apktool / jadx / dex2jar (releases) ----------------------------
if ! have apktool; then
  curl -fsSL https://raw.githubusercontent.com/iBotPeaches/Apktool/master/scripts/linux/apktool -o "$HOME/.local/tmp/apktool"
  gh_release iBotPeaches/Apktool@v3.0.3 'apktool_.*\.jar$' "$OPT_DIR/apktool/apktool.jar" \
    && install -m755 "$HOME/.local/tmp/apktool" "$BIN_DIR/apktool" \
    && ln -sf "$OPT_DIR/apktool/apktool.jar" "$BIN_DIR/apktool.jar" && ok "apktool installed"
fi
if [ ! -d "$OPT_DIR/jadx" ]; then
  if gh_release skylot/jadx@v1.5.6 'jadx-[0-9].*\.zip$' "$HOME/.local/tmp/jadx.zip"; then
    unzip -q -o "$HOME/.local/tmp/jadx.zip" -d "$OPT_DIR/jadx" \
      && shim jadx "$OPT_DIR/jadx/bin/jadx" && shim jadx-gui "$OPT_DIR/jadx/bin/jadx-gui"
  fi
fi
clone_or_pull https://github.com/pxb1988/dex2jar.git "$TOOLS_DIR/dex2jar"

ok "RE/binary toolkit installed."
