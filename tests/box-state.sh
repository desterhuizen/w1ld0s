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
set -uo pipefail

z="$HOME/.zshrc"

printf 'zshrc-md5    %s\n' "$( [ -f "$z" ] && md5sum "$z" | cut -d' ' -f1 || echo MISSING )"
printf 'zshrc-begin  %s\n' "$( grep -c '^# >>> w1ld0s >>>' "$z" 2>/dev/null || echo 0 )"
printf 'zshrc-end    %s\n' "$( grep -c '^# <<< w1ld0s <<<' "$z" 2>/dev/null || echo 0 )"
printf 'zshrc-gems   %s\n' "$( grep -c '  # gems$'         "$z" 2>/dev/null || echo 0 )"
printf 'login-shell  %s\n' "$( getent passwd "${USER:-$(id -un)}" 2>/dev/null | cut -d: -f7 )"

# Symlink set AND targets: a shim silently repointing is a real change.
printf 'bin-symlinks\n'
if [ -d "$HOME/.local/bin" ]; then
  find "$HOME/.local/bin" -maxdepth 1 -type l -printf '  %f -> %l\n' 2>/dev/null | sort
fi

# install_asset backs up to *.w1ld0s.bak before overwriting. A second run must
# create none: if it does, the module is rewriting a file it already owns.
printf 'backups\n'
find "$HOME" /etc -name '*.w1ld0s.bak' 2>/dev/null | sort | sed 's/^/  /'
