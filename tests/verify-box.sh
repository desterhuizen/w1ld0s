#!/usr/bin/env bash
# tests/verify-box.sh — verify a PROVISIONED w1ld0s box.
#
# Run this on the VM after ./bootstrap.sh and a reboot. It is the Tier 3 entry
# point: it asserts everything about the box that can be asserted from a shell,
# then prints the short list of things a human still has to look at.
#
#   ./tests/verify-box.sh              # auto-detect which modules ran
#   ./tests/verify-box.sh 00 35        # only these groups
#   ./tests/verify-box.sh -v --strict
#
# Run it INSIDE a desktop session if you want the GNOME group: gsettings needs
# a session bus and returns empty over SSH.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib.sh
source "$ROOT/tests/lib.sh"
parse_flags "$@" || exit $?
cd "$ROOT" || exit 1

rl() { sed -e 's/#.*//' -e 's/[[:space:]]*$//' -e '/^[[:space:]]*$/d' "$1"; }
have() { command -v "$1" >/dev/null 2>&1; }

# A group runs if it was named on the command line, or — when nothing was
# named — if the box carries evidence that its module ran. Someone who ran
# `./bootstrap.sh 00 10 90` must get skips for branding, not failures.
want() { # want <module-prefix> <auto-detect-cmd>
  local mod="$1"; shift
  if [ "${#TESTS_ARGS[@]}" -gt 0 ]; then
    local a; for a in "${TESTS_ARGS[@]}"; do [ "${mod#"$a"}" != "$mod" ] && return 0; done
    return 1
  fi
  eval "$*" >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
if want 00 'have pipx'; then
  section "Toolchain and Python isolation (00, 10, 20, 30, 40, 50)"

  if have pipx; then
    installed="$(pipx list --short 2>/dev/null | awk '{print $1}')"
    for m in tools.d/*.pipx; do
      while read -r name _; do
        [ -n "$name" ] || continue
        if printf '%s\n' "$installed" | grep -qix "$name"; then pass "pipx: $name"
        else fail "pipx: $name not installed (from $m)"; fi
      done < <(rl "$m")
    done
  else skip "pipx absent — Python tool checks skipped"; fi

  # go install drops binaries in ~/go/bin named for the last path segment,
  # after stripping the @version and any /vN module-major suffix.
  for m in tools.d/*.go; do
    while read -r spec; do
      [ -n "$spec" ] || continue
      p="${spec%@*}"; p="${p%/v[0-9]}"; b="${p##*/}"
      [ -x "$HOME/go/bin/$b" ] && pass "go: $b" || fail "go: $HOME/go/bin/$b missing (from $spec)"
    done < <(rl "$m")
  done

  # Only the persistent destinations. The .local/tmp rows are archives that
  # the modules unpack and discard, so their absence is correct.
  while read -r _ _ dest; do
    [ -n "$dest" ] || continue
    case "$dest" in
      .local/tmp/*) note "gh_release: $dest is a transient download, not checked" ;;
      *) [ -e "$HOME/$dest" ] && pass "gh_release: $dest" || fail "gh_release: ~/$dest missing" ;;
    esac
  done < <(rl tools.d/releases.gh)

  for c in nxc certipy impacket-secretsdump bloodhound-ce-python; do
    have "$c" && pass "on PATH: $c" || warn "not on PATH: $c"
  done

  if [ -n "${ROCKYOU:-}" ]; then
    [ -f "$ROCKYOU" ] && pass "\$ROCKYOU exists: $ROCKYOU" || fail "\$ROCKYOU set but missing: $ROCKYOU"
  else warn "\$ROCKYOU unset (run from an interactive shell that sourced ~/.zshrc)"; fi
fi

# ---------------------------------------------------------------------------
if want 00 'grep -q ">>> w1ld0s >>>" "$HOME/.zshrc"'; then
  section "Shell"

  s="$(getent passwd "${USER:-$(id -un)}" | cut -d: -f7)"
  [ "$s" = "/usr/bin/zsh" ] && pass "login shell is zsh" || fail "login shell is $s, expected /usr/bin/zsh"

  b="$(count_lines '^# >>> w1ld0s >>>' "$HOME/.zshrc")"
  e="$(count_lines '^# <<< w1ld0s <<<' "$HOME/.zshrc")"
  { [ "$b" = "1" ] && [ "$e" = "1" ]; } && pass "exactly one w1ld0s block in ~/.zshrc" \
    || fail "\$HOME/.zshrc has $b begin / $e end markers, expected 1 / 1"

  g="$(count_lines '  # gems$' "$HOME/.zshrc")"
  [ "$g" -le 1 ] && pass "at most one gems PATH line" || fail "\$HOME/.zshrc has $g '# gems' PATH lines"

  if have zsh; then
    # Colours are bash's on purpose; the block hands the same table to zsh.
    if diff <(bash -lic 'echo $LS_COLORS' 2>/dev/null | tail -1) \
            <(zsh  -ic  'echo $LS_COLORS' 2>/dev/null | tail -1) >/dev/null 2>&1
    then pass "LS_COLORS identical in bash and zsh"; else warn "LS_COLORS differ between bash and zsh"; fi

    # Any output other than "ok" is a broken line in ~/.zshrc.
    noise="$(zsh -ic 'echo ok' 2>&1 | grep -v '^ok$' || true)"
    [ -z "$noise" ] && pass "zsh starts cleanly" \
      || { fail "zsh startup emits output — broken line in ~/.zshrc:"; printf '%s\n' "$noise" | sed 's/^/       /'; }

    for a in htricks gtfo ysorerial; do
      # NB: the toolkit alias really is spelled `ysorerial`.
      zsh -ic "type $a" >/dev/null 2>&1 && pass "toolkit alias: $a" || warn "toolkit alias missing: $a"
    done
  else skip "zsh absent"; fi
fi

# ---------------------------------------------------------------------------
if want 35 'have nginx'; then
  section "Webserver (35)"

  if [ -w /var/www/html ]; then pass "/var/www/html writable without sudo"
  else fail "/var/www/html not writable by ${USER:-$(id -un)}"; fi

  if curl -sf -o /dev/null http://127.0.0.1/ 2>/dev/null || curl -s -o /dev/null http://127.0.0.1/ 2>/dev/null; then
    probe=/var/www/html/.w1ld0s-probe.txt
    printf 'probe\n' > "$probe" 2>/dev/null
    hdrs="$(curl -sI http://127.0.0.1/.w1ld0s-probe.txt 2>/dev/null)"
    for h in Server Date Last-Modified ETag; do
      printf '%s' "$hdrs" | grep -qi "^$h:" && fail "response leaks $h header" || pass "no $h header"
    done
    body="$(curl -s http://127.0.0.1/definitely-not-here 2>/dev/null | wc -c)"
    [ "$body" -eq 0 ] && pass "404 has an empty body" || fail "404 body is $body bytes, expected 0"
    rm -f "$probe"
  else skip "nothing listening on 127.0.0.1:80 — start nginx to check headers"; fi
fi

# ---------------------------------------------------------------------------
if want 06 '[ -d /usr/share/plymouth/themes/w1ld0s ]'; then
  section "Boot and greeter branding (06)"

  t=/usr/share/plymouth/themes/w1ld0s/w1ld0s.plymouth
  if [ -f "$t" ]; then
    grep -q 'ImageDir=.*/w1ld0s$' "$t" && pass "Plymouth ImageDir points at the w1ld0s theme" \
      || fail "Plymouth ImageDir is $(grep ImageDir "$t" 2>/dev/null) — must end in /w1ld0s"
  else fail "$t missing"; fi

  if sudo -n true 2>/dev/null; then
    sudo grep -qE '^GRUB_BACKGROUND=' /etc/default/grub && pass "GRUB_BACKGROUND set" || fail "GRUB_BACKGROUND not set"
    sudo grep -qE '^GRUB_TIMEOUT_STYLE=menu' /etc/default/grub && pass "GRUB_TIMEOUT_STYLE=menu" \
      || fail "GRUB_TIMEOUT_STYLE is not menu — the background never draws without it"
    for db in /var/lib/gdm3/greeter-dconf-defaults /var/lib/gdm/greeter-dconf-defaults; do
      [ -f "$db" ] || continue
      sudo strings "$db" 2>/dev/null | grep -q w1ld0s && pass "greeter dconf db carries w1ld0s" \
        || fail "$db has no w1ld0s entries — was it recompiled?"
    done
  else skip "no passwordless sudo — GRUB and greeter DB checks skipped"; fi
fi

# ---------------------------------------------------------------------------
if want 07 'have gsettings'; then
  section "GNOME session (07)"

  if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
    skip "no session bus — gsettings returns empty over SSH. Re-run inside a desktop session."
  else
    d=org.gnome.shell.extensions.dash-to-dock
    if gsettings writable "$d" dock-fixed >/dev/null 2>&1; then
      [ "$(gsettings get "$d" dock-fixed)" = "false" ] && pass "dock autohides" || fail "dock-fixed is not false"
    else skip "dash-to-dock schema absent"; fi

    f="$(gsettings get org.gnome.Ptyxis font-name 2>/dev/null || true)"
    case "$f" in *"Fira Code"*) pass "Ptyxis font: $f" ;; "") skip "Ptyxis schema absent" ;; *) warn "Ptyxis font is $f" ;; esac
  fi

  # The gsettings palette key stores a NAME, so it reads back 'w1ld0s'
  # whether or not the keyfile parsed. The file is the only real evidence.
  p="$HOME/.local/share/org.gnome.Ptyxis/palettes/w1ld0s.palette"
  if [ -f "$p" ]; then
    k="$(python3 -c "import configparser,sys;c=configparser.ConfigParser(strict=False);c.read(sys.argv[1]);print(len(c['Palette']) if c.has_section('Palette') else -1)" "$p" 2>/dev/null || echo err)"
    [ "$k" = "20" ] && pass "Ptyxis palette parses with 20 keys" || fail "Ptyxis palette has $k keys, expected 20"
  else warn "$p missing"; fi
fi

# ---------------------------------------------------------------------------
printf '\n%s== Still needs a human%s\n' "$_C_BLU" "$_C_OFF"
cat <<'EOF'
  Nothing below can be asserted from a shell. Check them by eye:

   1. REBOOT. The GRUB menu draws with the w1ld0s background (3s timeout),
      the Plymouth splash shows the watermark, and — on an encrypted root —
      the LUKS passphrase prompt still appears. This is the one place a bug
      is unrecoverable, so never skip it.
   2. Greeter: branded background, dark styling, w1ld0s banner. Both the
      GNOME and i3 sessions are listed.
   3. Log into GNOME: dock at the bottom and autohiding, the w1ld0s app
      folder populated, desktop icons gone. Close every Ptyxis window first,
      then reopen — it reads palettes only at startup.
   4. Log into i3: config loads, fonts render, i3blocks bar populated,
      wallpaper set.
   5. USB-passthrough a Wi-Fi or SDR adapter, then confirm aircrack-ng and
      hackrf_info see it.
   6. Run ./bootstrap.sh once more and confirm it changes nothing.
   7. Snapshot the VM as clean-base.
EOF

summarise
