#!/usr/bin/env bash
# tests/box-state.sh — print a canonical digest of the box state that a second
# ./bootstrap.sh run must NOT change.
#
#   ./tests/box-state.sh > /tmp/s1 && ./bootstrap.sh && ./tests/box-state.sh > /tmp/s2
#   diff /tmp/s1 /tmp/s2      # any output is an idempotence defect
#
# Deliberately NOT a filesystem tree diff: clone_or_pull fast-forwards every
# checkout on every run by design, and mtimes churn. This prints only the
# things that must be byte-stable, so the comparison is meaningful.
#
# This is a reporting script. It always exits 0 — its job is to emit a digest,
# and the caller compares two of them. Letting a traversal error become the
# exit status only breaks the caller.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib.sh
source "$ROOT/tests/lib.sh"

z="$HOME/.zshrc"

if [ -f "$z" ]; then
  printf 'zshrc-md5    %s\n' "$(md5sum "$z" | cut -d' ' -f1)"
else
  printf 'zshrc-md5    MISSING\n'
fi
printf 'zshrc-begin  %s\n' "$(count_lines '^# >>> w1ld0s >>>' "$z")"
printf 'zshrc-end    %s\n' "$(count_lines '^# <<< w1ld0s <<<' "$z")"
printf 'zshrc-gems   %s\n' "$(count_lines '  # gems$'         "$z")"
printf 'login-shell  %s\n' "$(getent passwd "${USER:-$(id -un)}" 2>/dev/null | cut -d: -f7)"

# Symlink set AND targets: a shim silently repointing is a real change.
printf 'bin-symlinks\n'
if [ -d "$HOME/.local/bin" ]; then
  find "$HOME/.local/bin" -maxdepth 1 -type l -printf '  %f -> %l\n' 2>/dev/null | sort || true
fi

# install_asset backs up to *.w1ld0s.bak before overwriting. A second run must
# create none: if it does, the module is rewriting a file it already owns.
#
# `|| true` is load-bearing. Under pipefail, find exits 1 the moment it cannot
# descend into a root-only directory — /etc/wireguard and /etc/ssl/private both
# exist once the provisioner has run — and that status would otherwise become
# this script's, failing the caller for no reason.
printf 'backups\n'
find "$HOME" /etc -name '*.w1ld0s.bak' 2>/dev/null | sort | sed 's/^/  /' || true

exit 0
