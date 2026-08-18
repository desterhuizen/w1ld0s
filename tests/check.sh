#!/usr/bin/env bash
# tests/check.sh — static checks over the w1ld0s repo. No box required, no
# network, no side effects: this is the per-push tier.
#
# TARGETS LINUX (bash 5 + GNU userland). It is deliberately not macOS
# compatible — run it through tests/check-docker.sh instead, which executes
# this exact script in the same container CI uses.
#
#   ./tests/check.sh            # quiet; prints only problems
#   ./tests/check.sh -v         # also print every passing check
#   ./tests/check.sh --strict   # warnings become failures
#
# set -u but never -e: every check must run, so one failure cannot mask the
# rest. Exit status comes from summarise().
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib.sh
source "$ROOT/tests/lib.sh"
parse_flags "$@" || exit $?
cd "$ROOT" || exit 1

# read_list's sed program, copied verbatim from lib/common.sh:277. The checker
# must see manifests exactly as the provisioner does — including #-to-EOL
# stripping, which several checks below are wrong without.
rl() { sed -e 's/#.*//' -e 's/[[:space:]]*$//' -e '/^[[:space:]]*$/d' "$1"; }

# Strip comments from shell source before grepping it for call sites. Without
# this, prose in comments ("read_list resolves names against tools.d/") is
# picked up as a call with an argument of "resolves".
uncomment() { sed -e 's/#.*//' "$@"; }

MODULE_FILES=(modules/*.sh)
SHELL_FILES=(bootstrap.sh lib/*.sh tests/*.sh "${MODULE_FILES[@]}")

# ---------------------------------------------------------------------------
section "Syntax and shape"

for f in "${SHELL_FILES[@]}"; do
  if bash -n "$f" 2>/dev/null; then pass "syntax $f"; else
    fail "bash -n $f"; bash -n "$f" 2>&1 | sed 's/^/       /'
  fi
done

# -x so shellcheck follows `source "$W1LD0S_ROOT/lib/common.sh"` and resolves
# the framework's helpers instead of drowning in SC2154.
if command -v shellcheck >/dev/null 2>&1; then
  # -S warning: gate on real defects, not on style notes. The repo's
# deliberate idioms (A && B || C, sourced-module `return || exit`) are
# documented as disables in .shellcheckrc so super-linter agrees with us.
if sc_out="$(shellcheck -x -s bash -S warning "${SHELL_FILES[@]}" 2>&1)"; then
    pass "shellcheck clean"
  else
    fail "shellcheck"; printf '%s\n' "$sc_out" | sed 's/^/       /'
  fi
else
  fail "shellcheck not installed — run via tests/check-docker.sh"
fi

[ -x bootstrap.sh ] && pass "bootstrap.sh executable" || fail "bootstrap.sh must be executable"

# Modules are sourced, so the bit is cosmetic — but it should be consistent.
mode_x=0; mode_n=0
for f in "${MODULE_FILES[@]}"; do
  if [ -x "$f" ]; then mode_x=$((mode_x + 1)); else mode_n=$((mode_n + 1)); fi
done
if [ "$mode_x" -eq 0 ] || [ "$mode_n" -eq 0 ]; then
  pass "module exec bits consistent"
else
  warn "module exec bits disagree ($mode_x executable, $mode_n not):"
  for f in "${MODULE_FILES[@]}"; do [ -x "$f" ] || printf '       0644 %s\n' "$f"; done
fi

for f in "${SHELL_FILES[@]}"; do
  if [ "$(head -1 "$f")" = "#!/usr/bin/env bash" ]; then pass "shebang $f"
  else warn "shebang: $f has '$(head -1 "$f")'"; fi
done

# ---------------------------------------------------------------------------
section "Manifest shape and pinning"

for f in tools.d/*.apt; do
  bad="$(rl "$f" | grep -vE '^[a-z0-9][a-z0-9+.-]*$' || true)"
  if [ -n "$bad" ]; then fail "$f: invalid package name(s):"; printf '%s\n' "$bad" | sed 's/^/       /'
  else pass "$f grammar"; fi
done

# Cross-file duplicates. `xclip` is in base.apt AND desktop.apt on purpose so
# desktop.apt installs standalone — hence WARN, not FAIL. Do not "fix" it.
dupes="$(cat tools.d/*.apt | rl /dev/stdin | sort | uniq -d || true)"
if [ -n "$dupes" ]; then warn "package(s) in more than one .apt manifest: $(echo "$dupes" | tr '\n' ' ')"
else pass "no cross-manifest apt duplicates"; fi

for f in tools.d/*.pipx; do
  while IFS= read -r line; do
    set -- $line
    if [ "$#" -lt 2 ]; then warn "$f: unpinned (no pip-spec): $line"; continue; fi
    case "$1" in *[=\<\>\[]*) fail "$f: field 1 must be the bare name: $line" ;; esac
    case "$line" in
      *--python*)
        if ! printf '%s' "$line" | grep -qE '\-\-python[[:space:]]+[0-9]+\.[0-9]+'; then
          fail "$f: --python without X.Y: $line"
        fi ;;
    esac
    case "$2" in
      *==*|git+*) pass "$f pinned: $1" ;;
      *) warn "$f: unpinned spec: $line" ;;
    esac
  done < <(rl "$f")
done

for f in tools.d/*.go; do
  while IFS= read -r line; do
    set -- $line
    [ "$#" -eq 1 ] || { fail "$f: expected one field: $line"; continue; }
    case "$1" in
      *@latest|*@master|*@main) warn "$f: unpinned: $1" ;;
      *@*) pass "$f pinned: $1" ;;
      *) fail "$f: missing @version: $1" ;;
    esac
  done < <(rl "$f")
done

# gh_release falls back to releases/latest when the spec carries no @tag
# (lib/common.sh:248-249), which silently defeats the lockfile.
for f in tools.d/*.gh; do
  while IFS= read -r line; do
    set -- $line
    [ "$#" -eq 3 ] || { fail "$f: expected 3 fields, got $#: $line"; continue; }
    case "$1" in *@*) : ;; *) fail "$f: unpinned (no @tag): $1" ;; esac
    # Field 2 must be a valid ERE once the arch placeholders are expanded.
    g="${2//@ARCH@/x86_64}"; g="${g//@ARCH_ALT@/amd64}"
    printf 'x\n' | grep -E "$g" >/dev/null 2>&1
    [ "$?" -le 1 ] || fail "$f: field 2 is not a valid ERE: $2"
    # Field 3 is passed to gh_release as a $HOME-relative destination.
    case "$3" in /*|*..*) fail "$f: dest must be \$HOME-relative: $3" ;; *) pass "$f row: $1" ;; esac
  done < <(rl "$f")
done

for f in tools.d/*.src; do
  if [ -s "$f" ] && [ -n "$(rl "$f")" ]; then
    fail "$f: .src is documentation only, but has non-comment lines:"; rl "$f" | sed 's/^/       /'
  else pass "$f is comment-only"; fi
done

# gnome.favorites/.folder carry the .desktop suffix; gnome.hide must not.
# The two conventions are opposite by design and a mismatch silently no-ops.
for f in tools.d/gnome.favorites tools.d/gnome.folder; do
  [ -f "$f" ] || continue
  bad="$(rl "$f" | grep -v '\.desktop$' || true)"
  [ -n "$bad" ] && { fail "$f: entries must end in .desktop:"; printf '%s\n' "$bad" | sed 's/^/       /'; } || pass "$f suffixes"
done
if [ -f tools.d/gnome.hide ]; then
  bad="$(rl tools.d/gnome.hide | grep '\.desktop' || true)"
  [ -n "$bad" ] && { fail "gnome.hide: entries must NOT carry .desktop:"; printf '%s\n' "$bad" | sed 's/^/       /'; } || pass "gnome.hide suffixes"
fi

for f in tools.d/*; do
  [ -f "$f" ] || continue
  d="$(rl "$f" | sort | uniq -d || true)"
  [ -n "$d" ] && warn "$f: duplicate entries: $(echo "$d" | tr '\n' ' ')" || pass "$f no dupes"
done

# git+ URLs must pin a ref, in manifests and in module source alike.
unpinned_git="$(grep -ohE 'git\+https://[^ "'"'"')]+' tools.d/*.pipx "${MODULE_FILES[@]}" 2>/dev/null | grep -v '@' || true)"
if [ -n "$unpinned_git" ]; then
  warn "git+ spec(s) with no @ref:"; printf '%s\n' "$unpinned_git" | sort -u | sed 's/^/       /'
else pass "all git+ specs pinned"; fi

# ---------------------------------------------------------------------------
section "https-only invariant"
# This is what lets a stranger provision with no SSH key and no GitHub account.

for f in tools.d/*.git; do
  [ -f "$f" ] || continue
  bad="$(rl "$f" | grep -vE '^https://' || true)"
  [ -n "$bad" ] && { fail "$f: non-https clone URL(s):"; printf '%s\n' "$bad" | sed 's/^/       /'; } || pass "$f all https"
done

# Allowlist behaviourally, not by line number, so it survives edits to
# modules/95-private.sh: comments, and `ssh -T git@github.com` auth probes.
stray="$(grep -rn 'git@' bootstrap.sh lib modules tools.d assets 2>/dev/null \
  | grep -vE ':[[:space:]]*#' | grep -vE 'ssh .*-T git@' || true)"
if [ -n "$stray" ]; then fail "git@ outside the ssh-probe allowlist:"; printf '%s\n' "$stray" | sed 's/^/       /'
else pass "no stray git@ URLs"; fi

literal="$(uncomment bootstrap.sh lib/*.sh "${MODULE_FILES[@]}" \
  | grep -ohE '(git clone|clone_or_pull)[[:space:]]+[^ ]*://[^ "'"'"']+' \
  | grep -oE '[a-z+]+://[^ "'"'"']+' | grep -vE '^https://' || true)"
if [ -n "$literal" ]; then fail "non-https literal clone URL(s):"; printf '%s\n' "$literal" | sed 's/^/       /'
else pass "literal clone URLs all https"; fi

# ---------------------------------------------------------------------------
section "Module registry and docs"

# Using diff rather than comm also enforces ORDER: the numeric prefixes make
# lexical order the intended run order, so a module inserted in the wrong slot
# of the array is a failure, not just a set difference.
mapfile -t ARRAY_MODS < <(sed -n '/^ALL_MODULES=(/,/^)/p' bootstrap.sh \
  | sed -e '1d' -e '$d' -e 's/#.*//' -e 's/[[:space:]]//g' -e '/^$/d')
mapfile -t DISK_MODS  < <(printf '%s\n' "${MODULE_FILES[@]}" | sed -e 's|.*/||' -e 's|\.sh$||')
mapfile -t DOC_MODS   < <(sed -n 's/^| `\([0-9][0-9]-[a-z0-9-]*\)` |.*/\1/p' docs/README.md)

if diff <(printf '%s\n' "${ARRAY_MODS[@]}") <(printf '%s\n' "${DISK_MODS[@]}") >/dev/null; then
  pass "ALL_MODULES matches modules/ (${#ARRAY_MODS[@]} modules, in order)"
else
  fail "ALL_MODULES vs modules/ (< array, > filesystem):"
  diff <(printf '%s\n' "${ARRAY_MODS[@]}") <(printf '%s\n' "${DISK_MODS[@]}") | sed 's/^/       /'
fi

if diff <(printf '%s\n' "${ARRAY_MODS[@]}") <(printf '%s\n' "${DOC_MODS[@]}") >/dev/null; then
  pass "docs/README.md module table matches ALL_MODULES"
else
  fail "docs/README.md module table drift (< array, > docs table):"
  diff <(printf '%s\n' "${ARRAY_MODS[@]}") <(printf '%s\n' "${DOC_MODS[@]}") | sed 's/^/       /'
fi

n="${#ARRAY_MODS[@]}"
for spec in "README.md:the \([0-9]\+\) modules" "docs/README.md:the \([0-9]\+\) provisioning steps"; do
  file="${spec%%:*}"; pat="${spec#*:}"
  found="$(sed -n "s/.*$pat.*/\1/p" "$file" | head -1)"
  if [ -z "$found" ]; then warn "$file: could not find the module count sentence"
  elif [ "$found" = "$n" ]; then pass "$file module count is $n"
  else fail "$file says $found modules, ALL_MODULES has $n"; fi
done

# ---------------------------------------------------------------------------
section "die traps"

# Invariant 2: a module must warn and continue. die() exits the whole run.
d="$(uncomment "${MODULE_FILES[@]}" | grep -nE '(^|[;&|[:space:]])die([[:space:]]|$)' || true)"
[ -n "$d" ] && { fail "die() called in a module:"; printf '%s\n' "$d" | sed 's/^/       /'; } || pass "no module calls die"

# The indirect version, and the one that actually bites: read_list die()s on a
# missing file (lib/common.sh:276), so a renamed manifest kills the bootstrap
# even though no module says die.
missing=0
while read -r arg; do
  [ -n "$arg" ] || continue
  [ "$arg" = "private.git" ] && continue   # gitignored by design; 95 guards it
  if [ -f "tools.d/$arg" ]; then pass "manifest exists: $arg"
  else fail "read_list/*_install_list references missing tools.d/$arg"; missing=1; fi
done < <(uncomment "${MODULE_FILES[@]}" \
  | grep -oE '(read_list|apt_install_list|pipx_install_list|go_install_list)[[:space:]]+[A-Za-z0-9._-]+' \
  | awk '{print $2}' | sort -u)
[ "$missing" -eq 0 ] || note "a missing manifest is fatal to the whole run, not just its module"

while read -r a; do
  [ -n "$a" ] || continue
  [ -e "assets/$a" ] && pass "asset exists: $a" || fail "install_asset references missing assets/$a"
done < <(uncomment "${MODULE_FILES[@]}" | grep -oE 'install_asset[[:space:]]+[A-Za-z0-9._/-]+' | awk '{print $2}' | sort -u)

while read -r spec; do
  [ -n "$spec" ] || continue
  case "$spec" in *@*) pass "inline gh_release pinned: $spec" ;; *) fail "inline gh_release with no @tag: $spec" ;; esac
done < <(uncomment "${MODULE_FILES[@]}" | grep -oE 'gh_release[[:space:]]+"?[A-Za-z0-9._/-]+/[A-Za-z0-9._-]+[^"[:space:]]*' | awk '{print $2}' | tr -d '"' | sort -u)

# ---------------------------------------------------------------------------
section "Secrets and gitignore integrity"

# Each alternative must be written so it cannot match THIS line — bracket a
# character in any pure literal ([O]PENSSH), or the scanner flags itself the
# moment this file is tracked. Keep that up when adding patterns.
pat='(-----BEGIN [A-Z ]*PRIVATE KEY|-----BEGIN [O]PENSSH|AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{22}|xox[baprs]-|AIza[0-9A-Za-z_-]{35}|sk-[A-Za-z0-9]{20,})'
hits="$(git ls-files -z | xargs -0 grep -InE "$pat" 2>/dev/null || true)"
[ -n "$hits" ] && { fail "possible secret in tracked files:"; printf '%s\n' "$hits" | sed 's/^/       /'; } || pass "no secret patterns in tracked files"

# .gitignore force-tracks tools.d with `!tools.d/*` and then re-ignores
# private.git AFTER it. Last matching rule wins, so the ORDER is load-bearing.
# --no-index throughout: git check-ignore consults the index by default and
# reports a TRACKED file as not-ignored regardless of the rules, which would
# make the force-tracking assertion below silently unfireable — exactly when
# it matters. --no-index tests the rules themselves.
if git check-ignore --no-index -q tools.d/private.git; then pass "tools.d/private.git is ignored"
else fail "tools.d/private.git is NOT ignored — check the rule order in .gitignore"; fi

# The rule can be right while the file is force-added anyway.
if git ls-files --error-unmatch tools.d/private.git >/dev/null 2>&1; then
  fail "tools.d/private.git is TRACKED — it must never enter git"
else pass "tools.d/private.git is not tracked"; fi

tracked="$(git ls-files -- '*.pem' '*.key' '*.p12' '*.pfx' '*.jks' 'id_rsa*' 'id_ecdsa*' 'id_ed25519*' '.env' '.envrc' '*.ovpn' '*.wgconf' '*.ccache' '*.kirbi' || true)"
[ -n "$tracked" ] && { fail "sensitive file(s) tracked:"; printf '%s\n' "$tracked" | sed 's/^/       /'; } || pass "no sensitive files tracked"

for f in tools.d/*; do
  [ -f "$f" ] || continue
  [ "$f" = "tools.d/private.git" ] && continue
  if git check-ignore --no-index -q "$f"; then fail "$f is ignored — the lockfile has silently stopped being tracked"
  else pass "$f is tracked"; fi
done

# ---------------------------------------------------------------------------
section "Assets"

# A stray \r survives read_list and becomes part of a package name.
crlf="$(git ls-files -z | xargs -0 grep -lI $'\r' 2>/dev/null || true)"
[ -n "$crlf" ] && { fail "CRLF line endings in:"; printf '%s\n' "$crlf" | sed 's/^/       /'; } || pass "no CRLF"

for j in assets/i3/*.json; do
  [ -f "$j" ] || continue
  python3 -m json.tool "$j" >/dev/null 2>&1 && pass "json parses: $j" || fail "invalid JSON: $j"
done

if [ -f assets/zshrc ]; then
  if command -v zsh >/dev/null 2>&1; then
    zsh -n assets/zshrc 2>/dev/null && pass "zsh -n assets/zshrc" || warn "zsh -n assets/zshrc failed"
  else skip "zsh not installed — cannot syntax-check assets/zshrc"; fi
fi

for c in assets/nginx/*.conf; do
  [ -f "$c" ] || continue
  o="$(tr -cd '{' < "$c" | wc -c)"; e="$(tr -cd '}' < "$c" | wc -c)"
  [ "$o" -eq "$e" ] && pass "nginx braces balanced: $c" || warn "nginx brace mismatch in $c ($o open, $e close)"
done

# The Ptyxis gsettings key stores a palette NAME, so it reads back 'w1ld0s'
# whether or not the keyfile parsed. The file is the only evidence.
for p in assets/ptyxis/*.palette; do
  [ -f "$p" ] || continue
  k="$(python3 - "$p" <<'PY' 2>/dev/null || true
import configparser, sys
c = configparser.ConfigParser(strict=False)
c.read(sys.argv[1])
print(len(c["Palette"]) if c.has_section("Palette") else -1)
PY
)"
  if [ "$k" = "20" ]; then pass "$p has a [Palette] with 20 keys"
  elif [ "$k" = "-1" ] || [ -z "$k" ]; then warn "$p: no [Palette] section, or it did not parse"
  else warn "$p has $k [Palette] keys, expected 20"; fi
done

# ---------------------------------------------------------------------------
section "lib/common.sh behaviour"
# Sourcing it runs the guards at lib/common.sh:65-66, which die on root or
# without sudo — so this group only runs as a normal user with sudo present.
if [ "$(id -u)" -eq 0 ]; then
  skip "running as root — lib/common.sh:65 would exit; behaviour checks skipped"
elif ! command -v sudo >/dev/null 2>&1; then
  skip "no sudo — lib/common.sh:66 would exit; behaviour checks skipped"
else
  if ( set +u; W1LD0S_ROOT="$ROOT"; export W1LD0S_ROOT
       . "$ROOT/lib/common.sh" >/dev/null 2>&1
       [ "$(_trim '   a  b   ')" = "a  b" ] || exit 1
       [ "$(read_list base.apt | head -1)" = "$(rl tools.d/base.apt | head -1)" ] || exit 1
       [ -n "$W1LD0S_ARCH" ] && [ -n "$W1LD0S_ARCH_ALT" ] || exit 1
     ); then pass "_trim / read_list / arch detection behave"
  else fail "lib/common.sh behaviour check"; fi
fi

summarise
