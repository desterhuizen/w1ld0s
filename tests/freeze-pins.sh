#!/usr/bin/env bash
# tests/freeze-pins.sh — print tools.d/* manifest lines carrying the versions
# THIS box is actually running, so freezing a green build back into the lockfile
# is a paste rather than fifty hand-transcriptions.
#
#   ./tests/freeze-pins.sh                  # every .pipx and .go manifest
#   ./tests/freeze-pins.sh ad.pipx web.go   # only these (bare filenames)
#   ./tests/freeze-pins.sh --diff           # unified diff, manifest vs box
#
# It is a line-preserving TRANSFORM, not a generator: every line comes through
# byte-identical except the version token. That is deliberate — the comments in
# tools.d/* carry reasoning the code does not ("donpapi removed: its pinned lxml
# cannot compile against the Python 3.14 C API"), and a generator would delete
# all of it. It is also what keeps `git diff tools.d/` reviewable afterwards.
#
# stdout is the PRODUCT; every message goes to stderr — same reasoning as
# lib/common.sh:38-46. tests/lib.sh is sourced ONLY for its box probes, which
# answer on stdout and print nothing else. Never call its pass/warn/note/skip
# from here: those print to stdout and would land in the middle of a manifest.
#
# Print, review, paste. There is deliberately no --write, and do NOT do
#     ./tests/freeze-pins.sh ad.pipx > tools.d/ad.pipx
# — the redirect truncates the file before the script has read it.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib.sh
source "$ROOT/tests/lib.sh"
cd "$ROOT" || exit 1

say() { printf '%s\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }

DIFF=0
ARGS=()
for a in "$@"; do
  case "$a" in
    --diff)    DIFF=1 ;;
    -h|--help) sed -n '2,22p' "$0" | sed 's/^#\{1,\} \{0,1\}//' >&2; exit 0 ;;
    -*)        say "unknown flag: $a"; exit 2 ;;
    *)         ARGS+=("$a") ;;
  esac
done

# Read the pipx inventory once rather than per manifest line.
PIPX_SHORT="$(pipx_short)"

# ---------------------------------------------------------------------------
# Per-format transforms. Each reads one manifest and writes it to stdout.
#
# Alignment is NOT recalculated: the whitespace run between the columns comes
# through verbatim, so a longer version shifts a column by a character or two.
# Re-padding is not worth the code.

# A line carries no entry if it is blank or its first non-space character is #.
_is_comment() { case "$(printf '%s' "$1" | tr -d '[:space:]')" in ''|'#'*) return 0 ;; esac; return 1; }

freeze_pipx() {  # freeze_pipx <manifest-path>
  local line name rest pad body pyver spec cur
  while IFS= read -r line || [ -n "$line" ]; do
    if _is_comment "$line"; then printf '%s\n' "$line"; continue; fi

    name="${line%%[[:space:]]*}"
    rest="${line#"$name"}"
    pad="${rest%%[![:space:]]*}"           # the alignment run, preserved verbatim
    body="${rest#"$pad"}"

    # "--python X.Y" is a directive, not part of the spec. No manifest uses it
    # today; pipx_install_list handles it, so this must too.
    spec="$(pipx_strip_python "$body")"
    pyver="${body%"$spec"}"

    case "$spec" in
      git+*)
        cur="$(pipx_source "$name")"
        if [ -n "$cur" ]; then
          printf '%s%s%s%s\n' "$name" "$pad" "$pyver" "$cur"
        else
          say "  $name: no pipx metadata on this box — line left as-is"
          printf '%s\n' "$line"
        fi
        ;;
      *==*)
        cur="$(pipx_version "$name" "$PIPX_SHORT")"
        if [ -n "$cur" ]; then
          printf '%s%s%s%s==%s\n' "$name" "$pad" "$pyver" "${spec%%==*}" "$cur"
        else
          say "  $name: not installed — pin left at ${spec##*==}"
          printf '%s\n' "$line"
        fi
        ;;
      *)
        cur="$(pipx_version "$name" "$PIPX_SHORT")"
        say "  $name: no pin in the manifest${cur:+ (box has $cur)} — line left as-is"
        printf '%s\n' "$line"
        ;;
    esac
  done < "$1"
}

freeze_go() {  # freeze_go <manifest-path>
  local line mod bin cur
  while IFS= read -r line || [ -n "$line" ]; do
    if _is_comment "$line"; then printf '%s\n' "$line"; continue; fi
    mod="${line%@*}"                       # the install path itself carries no @
    bin="$(go_bin "$mod")"
    cur="$(go_version "$bin")"
    if [ -n "$cur" ]; then
      printf '%s@%s\n' "$mod" "$cur"
    else
      say "  $bin: not installed or not a go binary — line left as-is"
      printf '%s\n' "$line"
    fi
  done < "$1"
}

# Returns non-zero when it produced no manifest on stdout, so the caller knows
# there is nothing to diff.
freeze_one() {  # freeze_one <bare-manifest-name>
  local f="tools.d/$1"
  [ -f "$f" ] || { say "no such manifest: $f"; return 2; }
  case "$1" in
    *.pipx) freeze_pipx "$f" ;;
    *.go)   freeze_go   "$f" ;;
    # .apt carries no versions by design; .gh would need a record of which tag
    # produced each artifact, and gh_release keeps none — see "Known gaps".
    *.apt)  say "$1: apt manifests carry no versions — skipped"; return 1 ;;
    *.gh)   say "$1: release tags are not recoverable from the files on disk — skipped"; return 1 ;;
    *)      say "$1: no freeze rule for this format — skipped"; return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
if [ "${#ARGS[@]}" -eq 0 ]; then
  for f in tools.d/*.pipx tools.d/*.go; do
    [ -f "$f" ] && ARGS+=("${f##*/}")
  done
fi
[ "${#ARGS[@]}" -gt 0 ] || { say "nothing to freeze"; exit 1; }

have pipx || say "pipx absent — .pipx manifests will come through unchanged"
have go   || say "go absent — .go manifests will come through unchanged"

rc=0        # 2 only for a manifest that does not exist; drift is not an error
drifted=0
for m in "${ARGS[@]}"; do
  if [ "$DIFF" -eq 1 ]; then
    tmp="$(mktemp)" || exit 1
    freeze_one "$m" > "$tmp"; st=$?
    if [ "$st" -eq 0 ]; then
      # diff exits 1 when the files differ, which is the interesting case here
      # and not an error. Label the sides so the direction is unambiguous.
      diff -u --label "tools.d/$m (manifest)" --label "tools.d/$m (this box)" \
        "tools.d/$m" "$tmp" || drifted=1
    elif [ "$st" -eq 2 ]; then
      rc=2
    fi
    rm -f "$tmp"
  else
    say "== tools.d/$m"
    freeze_one "$m"; st=$?
    [ "$st" -eq 2 ] && rc=2
  fi
done

if [ "$DIFF" -eq 1 ] && [ "$drifted" -eq 0 ] && [ "$rc" -eq 0 ]; then
  say "every pin matches this box"
fi
exit "$rc"
