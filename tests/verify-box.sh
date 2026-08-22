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

# A version mismatch is a WARN, not a FAIL. The tool works; what has stopped
# being true is that the manifests are the lockfile — the next VM built from
# this commit will not be this box. fail stays reserved for "not installed".
# Fix it either way round: bump the pin and rebuild, or ./tests/freeze-pins.sh
# to move the manifest onto what this box proved.
drift() {  # drift <what> <manifest> <pinned> <installed>
  if   [ -z "$4" ];     then warn "$1: installed version unknown (cannot compare with $3)"
  elif [ "$3" = "$4" ]; then pass "$1 $4 matches $2"
  else                       warn "$1: box has $4, $2 pins $3"; fi
}

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
  section "Toolchain and Python isolation (00, 10)"

  have pipx && pass "pipx present" || fail "pipx missing (module 10)"

  if [ -n "${ROCKYOU:-}" ]; then
    [ -f "$ROCKYOU" ] && pass "\$ROCKYOU exists: $ROCKYOU" || fail "\$ROCKYOU set but missing: $ROCKYOU"
  else warn "\$ROCKYOU unset (run from an interactive shell that sourced ~/.zshrc)"; fi
fi

# ---------------------------------------------------------------------------
# The OS underneath the toolkit. bootstrap.sh deliberately never runs
# `apt-get upgrade`, so this is the only place that says the box is behind.
if want 00 'have apt-get'; then
  section "OS state (00)"

  # Ubuntu's desktop install enables unattended-upgrades, so this is detection,
  # not prevention. Follows check_foreign_i386: report it and print the command,
  # never change it. 20auto-upgrades is the actual switch and is readable
  # without systemd, which `systemctl is-enabled` is not in a container.
  au=/etc/apt/apt.conf.d/20auto-upgrades
  if [ -f "$au" ] && grep -qs '^[^/]*APT::Periodic::Unattended-Upgrade[[:space:]]*"1"' "$au"; then
    warn "unattended-upgrades is enabled — this box can change itself mid-engagement"
    warn "  (an nginx ABI bump uninstalls the headers-more filter; a python3 point"
    warn "   release invalidates every pipx venv). Turn it off with:"
    warn "    sudo systemctl disable --now unattended-upgrades"
    warn "    sudo dpkg-reconfigure -plow unattended-upgrades"
  else
    pass "unattended-upgrades is not enabled"
  fi

  # Informational only, and honest about why: this reads the LOCAL apt index, so
  # it means nothing without a preceding `sudo apt-get update`. `apt`, not
  # `apt-get` — only the former has `list --upgradable`.
  if ! have apt; then
    skip "apt absent — upgradable count not read"
  else
    n="$(count_lines 'upgradable from' <(apt list --upgradable 2>/dev/null))"
    if [ "$n" -gt 0 ]; then
      note "$n apt package(s) upgradable against the local index. Refresh it with"
      note "  sudo apt-get update, then upgrade by hand — bootstrap.sh never does."
    else
      note "nothing upgradable against the local index (true only if apt-get update is recent)"
    fi
  fi
fi

# Each manifest is checked only when the module that installs it ran. Gating
# them all behind module 00 asserted every AD/web/cloud/RE tool on a box that
# had only run 00 07 10 90 95 99, which is 45 failures that mean nothing.
# The mapping is the module table in docs/README.md.

# Presence AND version: a box running impacket 0.12 against a manifest pinning
# 0.13.1 used to report fully green, because only the name was ever compared.
check_pipx() {  # check_pipx <manifest>
  local m="tools.d/$1" short name rest spec have_v
  [ -f "$m" ] || return 0
  have pipx || { skip "pipx absent — $1 not checked"; return 0; }
  short="$(pipx_short)"
  while read -r name rest; do
    [ -n "$name" ] || continue
    have_v="$(pipx_version "$name" "$short")"
    [ -n "$have_v" ] || { fail "pipx: $name not installed (from $m)"; continue; }
    spec="$(pipx_strip_python "$rest")"
    case "$spec" in
      # A git+ pin is a ref, not a version, and `pipx list` reports the package
      # version instead — so compare against the spec pipx recorded.
      git+*) drift "pipx $name" "$m" "$spec" "$(pipx_source "$name")" ;;
      *==*)  drift "pipx $name" "$m" "${spec##*==}" "$have_v" ;;
      # check.sh already complains about an unpinned manifest line; do not
      # duplicate that here, just say what the box is carrying.
      *)     note "pipx $name: $m carries no pin (box has $have_v)" ;;
    esac
  done < <(rl "$m")
}

# The manifest pins module@version; go_bin (tests/lib.sh) derives the binary
# name that `go install` actually wrote into ~/go/bin.
check_go() {  # check_go <manifest>
  local m="tools.d/$1" spec b cmp=1
  [ -f "$m" ] || return 0
  have go || { note "go absent — $1 checked for presence only"; cmp=0; }
  while read -r spec; do
    [ -n "$spec" ] || continue
    b="$(go_bin "${spec%@*}")"
    [ -x "$HOME/go/bin/$b" ] || { fail "go: $HOME/go/bin/$b missing (from $spec)"; continue; }
    if [ "$cmp" -eq 1 ]; then drift "go $b" "$m" "${spec##*@}" "$(go_version "$b")"
    else pass "go: $b"; fi
  done < <(rl "$m")
}

# pipx records the console scripts each package installed, so ask it rather than
# guessing that netexec ships nxc or pwntools ships pwn. One "<package>\t<app>"
# line per venv: an app named after the package if there is one, else the first —
# impacket alone ships around sixty and any single one proves the venv imports.
pipx_apps() {
  have pipx || return 0
  pipx list --json 2>/dev/null | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for name, meta in (d.get("venvs") or {}).items():
    apps = ((meta.get("metadata") or {}).get("main_package") or {}).get("apps") or []
    # Always emit a row, empty second field when the package ships no script:
    # that is what lets the caller tell "installed but nothing to run" apart
    # from "not installed at all", which check_pipx has already reported.
    print(name, next((a for a in apps if a.lower() == name.lower()), apps[0] if apps else ""), sep="\t")
'
}

# Assert the tool RUNS, not that it exits 0 — argparse-style CLIs disagree about
# what --help should exit with, but a broken venv is unambiguous: it tracebacks.
# This is the class that killed donpapi (lxml vs the 3.14 C API), wfuzz (pycurl
# vs 3.13) and ropper (ast.Str vs 3.12); all three installed cleanly and failed
# on first import, which check_pipx cannot see.
#
# pipx only, deliberately: a Go binary that execs at all has no import step to
# fail, and check_go already asserts -x on it.
smoke_pipx() {  # smoke_pipx <manifest> <pipx_apps-output>
  local m="tools.d/$1" apps="$2" name b out
  [ -f "$m" ] || return 0
  have pipx || return 0
  while read -r name _; do
    [ -n "$name" ] || continue
    b="$(printf '%s\n' "$apps" | awk -F'\t' -v p="$name" 'tolower($1)==tolower(p){print ($2==""?"-":$2); exit}')"
    # No row at all means the package is not installed, which check_pipx has
    # already failed on — do not say it twice.
    [ -n "$b" ] || continue
    [ "$b" = "-" ] && { note "smoke: $name ships no console script"; continue; }
    have "$b" || continue
    out="$(timeout 30 "$b" --help </dev/null 2>&1)"
    case "$out" in
      *"Traceback (most recent call last)"*|*ModuleNotFoundError*|*ImportError*)
        fail "smoke: $b fails to import (from $m)" ;;
      *) pass "smoke: $b runs" ;;
    esac
  done < <(rl "$m")
}

# Collected once: pipx list --json is slow enough that four calls are noticeable.
PIPX_APPS="$(pipx_apps)"

if want 20 'have nxc'; then section "AD and network tools (20)"; check_pipx ad.pipx; smoke_pipx ad.pipx "$PIPX_APPS"; fi
if want 30 'have ffuf'; then section "Web tools (30)"; check_pipx web.pipx; smoke_pipx web.pipx "$PIPX_APPS"; check_go web.go; fi
if want 40 'have aws'; then section "Cloud tools (40)"; check_pipx cloud.pipx; smoke_pipx cloud.pipx "$PIPX_APPS"; fi
if want 50 'have r2'; then section "RE and binary tools (50)"; check_pipx re.pipx; smoke_pipx re.pipx "$PIPX_APPS"; fi
if want 60 'have garble'; then section "Payload dev (60)"; check_go payload.go; fi

if want 80 '[ -d "$HOME/tools/binaries" ]'; then
  section "Release binaries (80)"
  # Only the persistent destinations. The .local/tmp rows are archives that the
  # modules unpack and discard, so their absence is correct.
  while read -r _ _ dest; do
    [ -n "$dest" ] || continue
    case "$dest" in
      .local/tmp/*) note "gh_release: $dest is a transient download, not checked" ;;
      *) [ -e "$HOME/$dest" ] && pass "gh_release: $dest" || fail "gh_release: ~/$dest missing" ;;
    esac
  done < <(rl tools.d/releases.gh)
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
if want 05 'have i3'; then
  section "Desktop and display manager (05)"

  # Module 05 switches unconditionally; gdm3 here means dpkg-reconfigure failed,
  # and the Wayland-everywhere behaviour that broke Chromium and Burp is back.
  dm="$(cat /etc/X11/default-display-manager 2>/dev/null || echo unset)"
  [ "$dm" = "/usr/sbin/lightdm" ] && pass "display manager is lightdm" \
    || fail "display manager is '$dm' — module 05 sets /usr/sbin/lightdm"
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
  else skip "no passwordless sudo — GRUB checks skipped"; fi

  # Branch on the active DM the way modules/06 does. This used to look only for
  # GDM's compiled dconf db and `continue` when it was absent, so on a lightdm
  # box the group reported green having checked no greeter at all.
  case "$(basename "$(cat /etc/X11/default-display-manager 2>/dev/null || echo unknown)")" in
    lightdm)
      lg=/etc/lightdm/lightdm-gtk-greeter.conf
      if [ -f "$lg" ]; then
        grep -q 'greeter-background.png' "$lg" && pass "lightdm greeter conf carries the w1ld0s background" \
          || fail "$lg has no w1ld0s background — run ./bootstrap.sh 06"
      else fail "$lg missing — is lightdm-gtk-greeter installed?"; fi
      ;;
    gdm3|gdm)
      if sudo -n true 2>/dev/null; then
        for db in /var/lib/gdm3/greeter-dconf-defaults /var/lib/gdm/greeter-dconf-defaults; do
          [ -f "$db" ] || continue
          sudo strings "$db" 2>/dev/null | grep -q w1ld0s && pass "greeter dconf db carries w1ld0s" \
            || fail "$db has no w1ld0s entries — was it recompiled?"
        done
      else skip "no passwordless sudo — greeter DB check skipped"; fi
      ;;
    *) warn "unknown display manager — greeter branding not checked" ;;
  esac
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
   2. Greeter: branded background, dark styling, and both the GNOME and i3
      sessions listed in the picker. The w1ld0s banner is a GDM-only key
      (org.gnome.login-screen banner-message-text) — lightdm has no banner.
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
