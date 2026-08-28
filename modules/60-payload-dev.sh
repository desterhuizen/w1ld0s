#!/usr/bin/env bash
# 60-payload-dev.sh — Payload dev / AV evasion: mingw cross-compile, wine, garble,
# SharpCollection, ysoserial, DotNetToJScript, RunasCs+mimikatz releases, veil, beef,
# and Metasploit Framework from Rapid7's nightly apt repo.
[ -n "${W1LD0S_ROOT:-}" ] || { W1LD0S_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; source "$W1LD0S_ROOT/lib/common.sh"; }

# --- cross-compile + wine ---------------------------------------------------
# i386 and the 32-bit toolchain are x86_64-only. Enabling the i386 architecture
# on arm64 is not merely useless (wine32 cannot execute x86 anyway) — it lets
# apt resolve gcc-multilib to gcc-multilib:i386 and evict the native compiler.
# See lib/common.sh apt_install (--no-remove) for the backstop.
if [ "$W1LD0S_ARCH" = "x86_64" ]; then
  sudo dpkg --add-architecture i386 2>/dev/null || true
  apt_install gcc-multilib g++-multilib libc6-dev-i386
  apt_install mingw-w64 gcc-mingw-w64 g++-mingw-w64 wine wine64 wine32 mono-complete
else
  warn "arch is $W1LD0S_ARCH: skipping i386/multilib, wine32 and mono (x86_64-only)."
  # mingw + 64-bit wine still have no arm64 story on Ubuntu; try, don't insist.
  apt_install mingw-w64 gcc-mingw-w64 g++-mingw-w64 || \
    warn "mingw cross-compile toolchain unavailable on $W1LD0S_ARCH — Windows payload builds will not work here."
fi

# --- garble (go obfuscator) -------------------------------------------------
export PATH="/usr/local/go/bin:$HOME/go/bin:$PATH"
go_install_list payload.go   # kerbrute, garble, glow (idempotent)

# --- prebuilt sharp tooling -------------------------------------------------
clone_or_pull https://github.com/Flangvik/SharpCollection.git "$REPOS_DIR/SharpCollection"

# --- ysoserial (jar) — the `ysorerial` alias expects ~/tools/binaries/ysoserial
if [ ! -f "$BINARIES_DIR/ysoserial/ysoserial.jar" ]; then
  gh_release frohoff/ysoserial@v0.0.6 'ysoserial-all\.jar$|ysoserial-.*\.jar$' "$BINARIES_DIR/ysoserial/ysoserial.jar" \
    && ok "ysoserial.jar installed"
fi

# --- DotNetToJScript (build target; the aliases point at ~/tools/binaries) ---
clone_or_pull https://github.com/tyranid/DotNetToJScript.git "$REPOS_DIR/DotNetToJScript"

# --- RunasCs (release zip) --------------------------------------------------
if [ ! -f "$BINARIES_DIR/runascs/RunasCs.exe" ]; then
  gh_release antonioCoco/RunasCs@v1.5 'RunasCs\.zip$' "$BINARIES_DIR/runascs/RunasCs.zip" \
    && unzip -q -o "$BINARIES_DIR/runascs/RunasCs.zip" -d "$BINARIES_DIR/runascs" && ok "RunasCs installed"
fi

# --- mimikatz (release zip) -------------------------------------------------
if [ ! -d "$BINARIES_DIR/mimikatz/x64" ]; then
  gh_release gentilkiwi/mimikatz@2.2.0-20220919 'mimikatz_trunk\.zip$' "$BINARIES_DIR/mimikatz/mimikatz_trunk.zip" \
    && unzip -q -o "$BINARIES_DIR/mimikatz/mimikatz_trunk.zip" -d "$BINARIES_DIR/mimikatz" && ok "mimikatz installed"
fi

# --- Metasploit Framework (nightly apt repo, added by hand) -----------------
# Rapid7 documents a one-liner that curls msfinstall out of raw.githubusercontent
# and runs it as root. On Debian/Ubuntu that script does exactly three things:
# dearmor its embedded signing key, write the sources.list line below, and
# apt-get install metasploit-framework. So we do those ourselves — same packages
# off the same repo, no unreviewed root script in the middle, and a re-run is an
# apt no-op instead of a re-download of the installer.
#
# The suite really is "lucid": Rapid7 has published one release pocket under
# that codename since 2015 and it is not tied to an Ubuntu version. msfinstall
# also writes /etc/apt/preferences.d/pin-metasploit.pref; that pin exists to win
# against a distro-packaged metasploit, and Ubuntu has never shipped one, so it
# is left out rather than carried as cargo.
MSF_KEYRING=/usr/share/keyrings/metasploit-framework.gpg
MSF_LIST=/etc/apt/sources.list.d/metasploit-framework.list
MSF_URI=https://downloads.metasploit.com/data/releases/metasploit-framework/apt

if [ ! -s "$MSF_KEYRING" ]; then
  log "Adding the Metasploit nightly apt repo…"
  if curl -fsSL https://apt.metasploit.com/metasploit-framework.gpg.key \
       | gpg --dearmor > /tmp/metasploit-framework.gpg 2>/dev/null; then
    sudo install -o root -g root -m 644 /tmp/metasploit-framework.gpg "$MSF_KEYRING" \
      || warn "metasploit: could not install the keyring"
  else
    warn "metasploit: could not fetch or dearmor the signing key"
  fi
  rm -f /tmp/metasploit-framework.gpg
fi

if [ ! -s "$MSF_KEYRING" ]; then
  warn "no $MSF_KEYRING — skipping metasploit-framework"
else
  # arch= is not cosmetic here. The repo advertises i386 alongside amd64/arm64,
  # and module 60 is the one module that enables the i386 architecture — an
  # i386 index plus i386 enabled is the state lib/common.sh's --no-remove guard
  # exists to survive. Pin the index to this box's architecture instead.
  MSF_LINE="deb [arch=$(dpkg --print-architecture) signed-by=$MSF_KEYRING] $MSF_URI lucid main"
  if [ "$(cat "$MSF_LIST" 2>/dev/null)" != "$MSF_LINE" ]; then
    printf '%s\n' "$MSF_LINE" | sudo tee "$MSF_LIST" >/dev/null
    _APT_UPDATED=0   # force the refresh that apt_install would otherwise skip
    log "wrote $MSF_LIST"
  fi
  # Presence-checked, unlike a normal apt_install. lucid is a rolling nightly and
  # apt_refresh runs at least once per bootstrap, so a bare `apt-get install -y`
  # would UPGRADE msf on any later run — a ~250MB download that swaps the
  # framework out mid-engagement. First install wins; the box keeps that build
  # until someone upgrades it deliberately.
  have msfconsole || apt_install metasploit-framework || warn "metasploit-framework install failed"
  # msfconsole runs without a database; only db_nmap, workspaces and the hosts/
  # services tables need one, and `msfdb init` wants postgresql, which nothing
  # here installs. Left to the operator on purpose — it is per-engagement state.
  have msfconsole && ok "metasploit installed (no database: sudo apt-get install postgresql && msfdb init)"
fi

# --- veil: dropped ----------------------------------------------------------
# Veil's setup.sh installs a 32-bit Wine prefix and Python-for-Windows, so it
# needs wine32 + mono — which this module already skips as x86_64-only. It was
# cloned anyway and left a "run setup.sh when ready" note that could never
# succeed on aarch64. Its generators are also unmaintained since 2021 and
# signatured everywhere; garble (above) and SharpCollection cover the ground.
# On x86_64 the recipe still lives in tools.d/kali-longtail.src if you want it.

# --- beef-xss (Kali long-tail, from source; ruby/bundler) -------------------
if [ ! -d "$TOOLS_DIR/beef" ]; then
  log "Cloning BeEF (run its ./install manually — installs ruby deps)…"
  clone_or_pull https://github.com/beefproject/beef.git "$TOOLS_DIR/beef"
  warn "BeEF: run '$TOOLS_DIR/beef/install' then edit config.yaml before first use."
fi

ok "payload-dev toolkit staged. BeEF needs its own (documented) setup step."
