#!/usr/bin/env bash
# tests/lib.sh — shared reporting scaffold for tests/check.sh and
# tests/verify-box.sh, plus the box probes verify-box.sh and freeze-pins.sh both
# need to read installed versions. Sourced, never executed.
#
# Deliberately NOT lib/common.sh: that one is the provisioner's framework and
# dies on root / missing sudo the moment it is sourced (lib/common.sh:65-66).
# The checkers must run in a container as root, so they get their own.
#
# Severity model:
#   fail  a broken invariant — exits non-zero
#   warn  a smell, or something intentional that a future reader should confirm
#   note  informational; never affects exit status
#   skip  not applicable in this environment (no session bus, module not run)
#
# --strict promotes warnings to failures. -v prints passes.

TESTS_FAILS=0
TESTS_WARNS=0
TESTS_SKIPS=0
TESTS_PASSES=0
TESTS_VERBOSE=0
TESTS_STRICT=0

# Colour only when stdout is a terminal, so CI logs stay clean.
if [ -t 1 ]; then
  _C_RED=$'\033[1;31m'; _C_YEL=$'\033[1;33m'; _C_GRN=$'\033[1;32m'
  _C_DIM=$'\033[2m';    _C_BLU=$'\033[1;34m'; _C_OFF=$'\033[0m'
else
  _C_RED=''; _C_YEL=''; _C_GRN=''; _C_DIM=''; _C_BLU=''; _C_OFF=''
fi

fail() { printf '%s[FAIL]%s %s\n' "$_C_RED" "$_C_OFF" "$*"; TESTS_FAILS=$((TESTS_FAILS + 1)); }
warn() { printf '%s[WARN]%s %s\n' "$_C_YEL" "$_C_OFF" "$*"; TESTS_WARNS=$((TESTS_WARNS + 1)); }
skip() { printf '%s[skip]%s %s\n' "$_C_DIM" "$_C_OFF" "$*"; TESTS_SKIPS=$((TESTS_SKIPS + 1)); }
note() { printf '%s[note]%s %s\n' "$_C_DIM" "$_C_OFF" "$*"; }
pass() {
  TESTS_PASSES=$((TESTS_PASSES + 1))
  [ "$TESTS_VERBOSE" -eq 1 ] && printf '%s[ ok ]%s %s\n' "$_C_GRN" "$_C_OFF" "$*"
  return 0
}
section() { printf '\n%s== %s%s\n' "$_C_BLU" "$*" "$_C_OFF"; }

# Count matching lines, safely.
#
# `grep -c` PRINTS "0" and EXITS 1 when nothing matches, so the obvious
# `$(grep -c ... || echo 0)` runs both sides and yields a two-line "0\n0" —
# which then breaks any numeric test that consumes it. Always use this.
count_lines() {  # count_lines <pattern> <file>
  local n
  n="$(grep -c "$1" "$2" 2>/dev/null)" || n=0
  printf '%s' "${n:-0}"
}

# Parse common flags. Callers pass "$@" and use the remaining args via
# TESTS_ARGS afterwards, so a script can take positional args of its own.
TESTS_ARGS=()
parse_flags() {
  while [ $# -gt 0 ]; do
    case "$1" in
      -v|--verbose) TESTS_VERBOSE=1 ;;
      --strict)     TESTS_STRICT=1 ;;
      -h|--help)    return 10 ;;
      --)           shift; TESTS_ARGS+=("$@"); return 0 ;;
      -*)           printf 'unknown flag: %s\n' "$1" >&2; return 11 ;;
      *)            TESTS_ARGS+=("$1") ;;
    esac
    shift
  done
  return 0
}

# ---- box probes ------------------------------------------------------------
# What a PROVISIONED box reports for a tool it has installed. Shared by
# verify-box.sh (which compares these against the manifests) and freeze-pins.sh
# (which prints them back out in manifest shape), so the two cannot drift apart.
#
# These return their answer on STDOUT and print nothing else, deliberately —
# freeze-pins.sh's stdout is a manifest. They use `command -v` rather than a
# `have` helper so this file stays free of dependencies on its callers.

# `pipx list --short` prints "name version", one per line. Callers that check a
# whole manifest should capture it once rather than calling this in a loop.
pipx_short() { command -v pipx >/dev/null 2>&1 && pipx list --short 2>/dev/null; }

# PyPI normalises names, so the manifest's "bloodyAD" is pipx's "bloodyad".
pipx_version() {  # pipx_version <manifest-name> [pipx-list-short-output]
  local short="${2:-$(pipx_short)}"
  [ -n "$short" ] || return 0
  printf '%s\n' "$short" | awk -v n="$1" 'tolower($1)==tolower(n){print $2; exit}'
}

# For a git+ pin the installed REF is what matters, and `pipx list` reports a
# package version instead. pipx records the spec it installed from; read that.
# python3 rather than jq — both are in base.apt, but verify-box.sh already sets
# the precedent of parsing box state with an inline python3 -c.
#
# .main_package.package_or_url is pipx internals, not a documented interface.
# If it moves, this returns empty and the caller reports "version unknown".
pipx_source() {  # pipx_source <manifest-name>
  local d="$HOME/.local/share/pipx/venvs" m c
  m="$d/$1/pipx_metadata.json"
  if [ ! -f "$m" ] && [ -d "$d" ]; then
    c="$(find "$d" -maxdepth 1 -mindepth 1 -type d -iname "$1" 2>/dev/null | head -n1)"
    [ -n "$c" ] && m="$c/pipx_metadata.json"
  fi
  [ -f "$m" ] || return 0
  python3 -c 'import json,sys
try:
    print(json.load(open(sys.argv[1])).get("main_package", {}).get("package_or_url") or "")
except Exception:
    pass' "$m" 2>/dev/null
}

# go install drops the binary in ~/go/bin named for the last path segment, after
# stripping any /vN module-major suffix. Without the strip, dalfox/v2 would look
# for a binary called "v2".
go_bin() { local p="${1%/v[0-9]}"; printf '%s' "${p##*/}"; }

# `go version -m` reports the module version on a "mod <path> <version>" line.
go_version() {  # go_version <binary-name>
  command -v go >/dev/null 2>&1 || return 0
  [ -x "$HOME/go/bin/$1" ] || return 0
  go version -m "$HOME/go/bin/$1" 2>/dev/null | awk '$1=="mod"{print $3; exit}'
}

# Strip a leading "--python X.Y" directive off a .pipx spec column. The
# directive lives in the manifest so every interpreter exception is visible
# where the tool is declared; it is not part of the pip spec.
pipx_strip_python() {  # pipx_strip_python <spec-column>
  local s="$1"
  [[ "$s" =~ ^--python[=[:space:]]+[0-9]+\.[0-9]+[[:space:]]+(.*)$ ]] && s="${BASH_REMATCH[1]}"
  printf '%s' "$s"
}

# Print the tally and exit with the right status. Call as the last line.
summarise() {
  printf '\n'
  printf '%s passed, %s failed, %s warned, %s skipped\n' \
    "$TESTS_PASSES" "$TESTS_FAILS" "$TESTS_WARNS" "$TESTS_SKIPS"
  if [ "$TESTS_FAILS" -gt 0 ]; then
    printf '%sFAILED%s\n' "$_C_RED" "$_C_OFF"
    exit 1
  fi
  if [ "$TESTS_STRICT" -eq 1 ] && [ "$TESTS_WARNS" -gt 0 ]; then
    printf '%sFAILED (--strict: warnings are errors)%s\n' "$_C_RED" "$_C_OFF"
    exit 1
  fi
  printf '%sOK%s\n' "$_C_GRN" "$_C_OFF"
  exit 0
}
