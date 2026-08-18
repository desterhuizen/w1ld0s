#!/usr/bin/env bash
# 20-ad-network.sh — Core AD / network toolkit. Isolated pipx venvs + a dedicated
# BloodHound-CE ingestor venv with a sign/seal-capable ldap3 (fixes today's bug).
[ -n "${W1LD0S_ROOT:-}" ] || { W1LD0S_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; source "$W1LD0S_ROOT/lib/common.sh"; }

# --- isolated pipx CLI tools ------------------------------------------------
log "Installing AD/network pipx tools (one venv each)…"
pipx_install_list ad.pipx

# --- go tools shared with payload module (kerbrute lives here) --------------
export PATH="/usr/local/go/bin:$HOME/go/bin:$PATH"
go_install_list payload.go   # kerbrute, garble, glow (idempotent; also called in 60)

# --- responder (git; needs Linux, not on PyPI in a usable form) -------------
clone_or_pull https://github.com/lgandx/Responder.git "$TOOLS_DIR/Responder"
[ -f "$TOOLS_DIR/Responder/Responder.py" ] && shim responder-run "$TOOLS_DIR/Responder/Responder.py"

# --- krbrelayx (dirkjanm) ----------------------------------------------------
clone_or_pull https://github.com/dirkjanm/krbrelayx.git "$TOOLS_DIR/krbrelayx"

# --- kerberoast scripts (Kali long-tail, from source) -----------------------
clone_or_pull https://github.com/nidem/kerberoast.git "$TOOLS_DIR/kerberoast"

# --- crowbar (Kali long-tail, isolated via pipx from git) -------------------
pipx_tool crowbar "git+https://github.com/galkan/crowbar@v4.1"

# --- evil-winrm (ruby gem, user install) ------------------------------------
if ! have evil-winrm; then
  log "Installing evil-winrm (gem, user)…"
  gem install --user-install evil-winrm -v 3.9 || warn "evil-winrm gem failed"
fi

# The gem bin dir goes on PATH on EVERY run, not only the run that installs the
# gem: `have evil-winrm` is true from the second run onward, so nesting this
# inside that guard meant a box whose ~/.zshrc line was lost never got it back.
#
# This was `[ -d "$gembin" ] && grep -q … || echo … >>`, where the `||` fires
# when the LEFT side fails too — a missing gem dir appended a PATH entry for a
# directory that does not exist. Two traps in the original, both fixed here:
#   * `$(ruby -e …)/bin` collapses to the literal "/bin" when ruby is absent or
#     errors, and /bin passes `-d`, so the check could not catch it. Capture the
#     directory first and test that it is non-empty.
#   * `grep -q` on a path treats it as a regex; -F matches it literally.
if have ruby; then
  gemdir="$(ruby -e 'require "rubygems"; print Gem.user_dir' 2>/dev/null)"
  if [ -n "$gemdir" ] && [ -d "$gemdir/bin" ]; then
    gembin="$gemdir/bin"
    if grep -qF "$gembin" "$HOME/.zshrc" 2>/dev/null; then
      log "gem bin dir already on PATH in ~/.zshrc"
    elif grep -q '  # gems$' "$HOME/.zshrc" 2>/dev/null; then
      # Gem.user_dir carries ruby's ABI version (…/gem/ruby/3.3.0/bin), so a
      # ruby upgrade moves it. Rewrite the marked line instead of stacking a
      # second export that leaves the dead path ahead of the live one.
      sed -i "s|^export PATH=.*  # gems\$|export PATH=\"$gembin:\$PATH\"  # gems|" "$HOME/.zshrc"
      ok "gem bin PATH in ~/.zshrc repointed to $gembin"
    else
      printf 'export PATH="%s:$PATH"  # gems\n' "$gembin" >> "$HOME/.zshrc"
      ok "added $gembin to PATH in ~/.zshrc"
    fi
  else
    warn "no gem user bin dir (${gemdir:-ruby produced no path}) — PATH left alone"
  fi
fi

# --- BloodHound-CE ingestor in a DEDICATED venv with sign-capable ldap3 ------
# This is the fix for the signing-enforced / no-LDAPS-cert DC that broke today.
# bloodhound-ce (dirkjanm CE branch) collects CE-format JSON to upload to your
# separate BloodHound CE host. We pin a sign/seal-capable ldap3 into the venv.
log "Building BloodHound-CE ingestor venv (sign-capable ldap3)…"
BHCE_VENV="$(venv_create bloodhound-ce bloodhound-ce)"
# Prefer the ly4k ldap3 fork (adds TLS channel binding); for plain-389 signing on
# a DC with no LDAPS cert, use Kerberos (-k) — see docs/ad-collection-cheatsheet.md.
"$BHCE_VENV/bin/pip" install -q --upgrade "git+https://github.com/ly4k/ldap3" 2>/dev/null \
  || warn "patched ldap3 install failed; stock ldap3 remains (Kerberos path still works)"
if [ -x "$BHCE_VENV/bin/bloodhound-ce-python" ]; then
  shim bloodhound-ce-python "$BHCE_VENV/bin/bloodhound-ce-python"
elif [ -x "$BHCE_VENV/bin/bloodhound-python" ]; then
  shim bloodhound-ce-python "$BHCE_VENV/bin/bloodhound-python"
fi

ok "AD/network toolkit installed. See docs/ad-collection-cheatsheet.md for signing-enforced DCs."
