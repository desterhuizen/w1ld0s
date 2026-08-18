#!/usr/bin/env bash
# 30-web.sh — Web-app toolkit: go tools, feroxbuster (release), sqlmap/joomscan
# (git), pipx tools, wpscan (gem), Burp Suite Community (official installer).
[ -n "${W1LD0S_ROOT:-}" ] || { W1LD0S_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; source "$W1LD0S_ROOT/lib/common.sh"; }

export PATH="/usr/local/go/bin:$HOME/go/bin:$PATH"

# --- go web tools -----------------------------------------------------------
log "Installing web go tools…"
go_install_list web.go
# nuclei templates
have "$HOME/go/bin/nuclei" && "$HOME/go/bin/nuclei" -update-templates >/dev/null 2>&1 || true

# --- feroxbuster (release binary) -------------------------------------------
if ! have feroxbuster; then
  # .zip is the one format published for every arch (x86_64 also has .tar.gz).
  if gh_release epi052/feroxbuster@v2.13.1 "@ARCH@-linux-feroxbuster\.zip$" "$HOME/.local/tmp/feroxbuster.zip"; then
    unzip -q -o "$HOME/.local/tmp/feroxbuster.zip" feroxbuster -d "$HOME/.local/tmp" \
      && install -m755 "$HOME/.local/tmp/feroxbuster" "$BIN_DIR/feroxbuster" \
      && ok "feroxbuster installed" || warn "feroxbuster unpack failed"
  fi
fi

# --- sqlmap + joomscan (git) ------------------------------------------------
clone_or_pull https://github.com/sqlmapproject/sqlmap.git "$TOOLS_DIR/sqlmap"
[ -f "$TOOLS_DIR/sqlmap/sqlmap.py" ] && shim sqlmap "$TOOLS_DIR/sqlmap/sqlmap.py"
clone_or_pull https://github.com/OWASP/joomscan.git "$TOOLS_DIR/joomscan"

# --- whatweb (git + one gem) ------------------------------------------------
# Cloned, not apt-installed: the distro package is still 0.5.5 (upstream's 2020
# release) while upstream is on 0.6.x, and whatweb's value is its plugin corpus
# — a checkout updates plugins with `git pull`, a .deb freezes them until the
# next Ubuntu release.
#
# lib/gems.rb hard-requires ipaddr, addressable and json, and prints "not
# installed" + exit 1 if any is missing. ipaddr and json are ruby default gems;
# addressable is not. wpscan happens to pull it in above, but that is an
# accident of ordering, so ask for it by name.
if have gem; then
  if gem list -i addressable >/dev/null 2>&1; then
    log "ruby addressable gem already present"
  else
    log "Installing addressable (gem, user) — whatweb hard-requires it…"
    gem install --user-install addressable -v 2.9.0 >/dev/null 2>&1 \
      || warn "addressable gem failed — whatweb will exit 1 on start"
  fi
else
  warn "no gem command — whatweb needs the addressable gem and will not run"
fi
clone_or_pull https://github.com/urbanadventurer/WhatWeb.git "$TOOLS_DIR/whatweb"
# A bare symlink shim is safe here: whatweb finds its own lib/ and plugins/ via
# __dir__, which is File.dirname(File.realpath(__FILE__)) and so resolves the
# symlink — the same reason sqlmap's os.path.realpath shim works above. A tool
# that used File.dirname(__FILE__) would need a wrapper instead.
[ -f "$TOOLS_DIR/whatweb/whatweb" ] && shim whatweb "$TOOLS_DIR/whatweb/whatweb"

# --- pipx web tools ---------------------------------------------------------
log "Installing web pipx tools…"
pipx_install_list web.pipx

# --- wpscan (gem) -----------------------------------------------------------
if ! have wpscan; then
  log "Installing wpscan (gem, user)…"
  gem install --user-install wpscan -v 4.1.0 || warn "wpscan gem failed"
fi

# --- Burp Suite Community (official Linux installer, headless EULA) ----------
if ! have BurpSuiteCommunity && [ ! -d "$OPT_DIR/BurpSuiteCommunity" ]; then
  log "Fetching Burp Suite Community installer…"
  # PortSwigger ships two Linux installers and 'type=Linux' is the x86_64 one —
  # it bundles its own x86_64 JRE, so on aarch64 it unpacked fine and then died
  # with "Exec format error" the moment it launched that JRE. Pick by host arch.
  case "$W1LD0S_ARCH" in
    aarch64) burp_type=LinuxArm64 ;;
    *)       burp_type=Linux ;;
  esac
  burp_url="https://portswigger.net/burp/releases/download?product=community&type=$burp_type"
  if curl -fsSL "$burp_url" -o "$HOME/.local/tmp/burp-community.sh" 2>/dev/null; then
    chmod +x "$HOME/.local/tmp/burp-community.sh"
    # -q -overwrite -dir <path> runs the install4j installer unattended
    "$HOME/.local/tmp/burp-community.sh" -q -overwrite -dir "$OPT_DIR/BurpSuiteCommunity" 2>/dev/null \
      && shim burp "$OPT_DIR/BurpSuiteCommunity/BurpSuiteCommunity" \
      || warn "Burp unattended install failed — run $HOME/.local/tmp/burp-community.sh by hand"
  else
    warn "Burp download failed (page may need a browser) — install manually from portswigger.net"
  fi
fi

ok "web toolkit installed."
