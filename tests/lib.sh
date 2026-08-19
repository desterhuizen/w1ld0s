#!/usr/bin/env bash
# tests/lib.sh — shared reporting scaffold for tests/check.sh and
# tests/verify-box.sh. Sourced, never executed.
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
