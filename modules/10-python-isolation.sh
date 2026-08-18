#!/usr/bin/env bash
# 10-python-isolation.sh — enforce and document the Python isolation policy.
# This module installs nothing heavy; it makes sure pipx + the shared venv dir
# are ready and records WHY every Python tool is isolated (the reason w1ld0s exists).
[ -n "${W1LD0S_ROOT:-}" ] || { W1LD0S_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; source "$W1LD0S_ROOT/lib/common.sh"; }

have pipx || apt_install pipx
pipx ensurepath >/dev/null 2>&1 || true
mkdir -p "$VENV_DIR"

cat <<EOF
$(printf '\033[1;33m')POLICY — Python tool isolation (do not violate)$(printf '\033[0m')
  * NEVER 'apt install' a Python security tool, and NEVER 'pip install --user'.
    Kali's netexec->bloodhound.py coupling and the un-signable distro ldap3 are
    exactly what a shared site-packages produces.
  * Each CLI tool -> its own pipx venv:            pipx install <tool>
  * A toolkit needing patched/pinned deps -> venv: $VENV_DIR/<name>
      (e.g. the BloodHound-CE ingestor with a sign/seal-capable ldap3 — module 20)
  * Tool sets are declared in tools.d/*.pipx and installed by their module.
Shared venv dir: $VENV_DIR
pipx venvs:      \$HOME/.local/share/pipx/venvs (one per tool)
EOF

ok "python isolation ready. pipx: $(pipx --version 2>/dev/null || echo n/a)"
