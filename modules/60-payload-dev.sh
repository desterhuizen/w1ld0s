#!/usr/bin/env bash
# 60-payload-dev.sh — Payload dev / AV evasion: mingw cross-compile, wine, garble,
# SharpCollection, ysoserial, DotNetToJScript, RunasCs+mimikatz releases, veil, beef.
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
