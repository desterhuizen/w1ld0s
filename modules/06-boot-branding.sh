#!/usr/bin/env bash
# 06-boot-branding.sh — replace the distro boot branding with the w1ld0s logo:
#   * GRUB menu background   (/etc/default/grub -> GRUB_BACKGROUND)
#   * Plymouth boot splash   (the animated logo Ubuntu shows while booting)
#
# The Plymouth theme is a COPY of Ubuntu's own 'spinner' theme with only the
# watermark image swapped. That keeps Ubuntu's tested script — including the
# LUKS passphrase prompt — instead of a hand-written one that could leave an
# encrypted machine with no way to enter its password.
#
# Touches boot configuration and regenerates the initramfs. Re-runnable.
[ -n "${W1LD0S_ROOT:-}" ] || { W1LD0S_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; source "$W1LD0S_ROOT/lib/common.sh"; }

BRAND="$W1LD0S_ROOT/assets/branding"
[ -f "$BRAND/w1ld0s-grub.png" ]   || { warn "missing $BRAND/w1ld0s-grub.png";   return 0 2>/dev/null || exit 0; }
[ -f "$BRAND/w1ld0s-splash.png" ] || { warn "missing $BRAND/w1ld0s-splash.png"; return 0 2>/dev/null || exit 0; }

apt_install plymouth plymouth-themes plymouth-label

# ---------------------------------------------------------------------------
# GRUB menu background
# ---------------------------------------------------------------------------
GRUB_DEFAULTS=/etc/default/grub
GRUB_IMG=/boot/grub/w1ld0s-grub.png

log "Installing GRUB background…"
sudo install -D -m644 "$BRAND/w1ld0s-grub.png" "$GRUB_IMG"

# Set or replace a key in /etc/default/grub, whether it is present, commented, or absent.
set_grub_kv() {
  local key="$1" val="$2"
  if sudo grep -qE "^[#[:space:]]*${key}=" "$GRUB_DEFAULTS"; then
    sudo sed -i -E "s|^[#[:space:]]*${key}=.*|${key}=${val}|" "$GRUB_DEFAULTS"
  else
    printf '%s=%s\n' "$key" "$val" | sudo tee -a "$GRUB_DEFAULTS" >/dev/null
  fi
}

set_grub_kv GRUB_BACKGROUND "\"$GRUB_IMG\""
set_grub_kv GRUB_GFXMODE    "\"1920x1080,1280x720,auto\""
# gfxpayload=keep hands the framebuffer to the kernel so plymouth starts without a mode switch.
set_grub_kv GRUB_GFXPAYLOAD_LINUX "keep"

# Ubuntu ships GRUB_TIMEOUT=0 + GRUB_TIMEOUT_STYLE=hidden on a single-OS box, so
# the menu — and therefore the background we just installed — never draws at all.
# Three seconds is enough to see it and to reach recovery mode.
set_grub_kv GRUB_TIMEOUT_STYLE "menu"
set_grub_kv GRUB_TIMEOUT       "3"

# GRUB_DISTRIBUTOR is deliberately LEFT ALONE. It feeds --bootloader-id, so on an
# EFI box renaming it can leave a second /boot/efi/EFI/<name> tree behind on the
# next grub-efi update — a real boot-path risk for a cosmetic menu title.

# A background only renders under gfxterm. An active 'GRUB_TERMINAL=console'
# forces text mode and silently discards the image, so comment it out.
if sudo grep -qE '^[[:space:]]*GRUB_TERMINAL(_OUTPUT)?=.*console' "$GRUB_DEFAULTS"; then
  sudo sed -i -E 's|^([[:space:]]*GRUB_TERMINAL(_OUTPUT)?=.*console.*)$|#\1  # w1ld0s: console mode hides GRUB_BACKGROUND|' "$GRUB_DEFAULTS"
  log "commented out GRUB_TERMINAL=console (it would hide the background)"
fi

# Plymouth only draws if the kernel is booted with 'quiet splash'.
if ! sudo grep -qE '^GRUB_CMDLINE_LINUX_DEFAULT=.*splash' "$GRUB_DEFAULTS"; then
  set_grub_kv GRUB_CMDLINE_LINUX_DEFAULT "\"quiet splash\""
  log "added 'quiet splash' to the kernel command line (required for the splash)"
fi

sudo update-grub >/dev/null 2>&1 && ok "GRUB background installed" || warn "update-grub failed"

# ---------------------------------------------------------------------------
# Plymouth splash — clone the stock spinner theme, swap the watermark
# ---------------------------------------------------------------------------
SPINNER=/usr/share/plymouth/themes/spinner
THEME=/usr/share/plymouth/themes/w1ld0s

if [ -d "$SPINNER" ]; then
  log "Building the w1ld0s Plymouth theme from the stock spinner theme…"
  sudo rm -rf "$THEME"
  sudo cp -a "$SPINNER" "$THEME"
  [ -f "$THEME/spinner.plymouth" ] && sudo mv "$THEME/spinner.plymouth" "$THEME/w1ld0s.plymouth"
  # ImageDir is set OUTRIGHT, not rewritten by string match. Ubuntu 26.04 ships
  # 'ImageDir=/usr/share/plymouth/themes//spinner' — note the double slash — so
  # the 's|themes/spinner|themes/w1ld0s|' below never matched it and the theme
  # silently kept loading the stock Ubuntu watermark out of the spinner dir.
  # Every asset we care about lives in $THEME, so just point it there.
  # Name[xx]= are the upstream localized "Spinner" strings; drop them or the
  # splash still says Spinner in every locale but English.
  sudo sed -i -E \
    -e '/^Name\[/d' \
    -e 's|^Name=.*|Name=w1ld0s|' \
    -e 's|^Description=.*|Description=w1ld0s boot splash|' \
    -e "s|^ImageDir=.*|ImageDir=$THEME|" \
    -e 's|themes/+spinner|themes/w1ld0s|g' \
    "$THEME/w1ld0s.plymouth"

  # The watermark is the logo the spinner theme renders. Ubuntu ships its own here.
  sudo install -m644 "$BRAND/w1ld0s-splash.png" "$THEME/watermark.png"
  # Some Ubuntu builds look for these names instead; provide them all.
  sudo install -m644 "$BRAND/w1ld0s-splash.png" "$THEME/ubuntu-logo.png" 2>/dev/null || true
  sudo install -m644 "$BRAND/w1ld0s-splash.png" /usr/share/plymouth/ubuntu-logo.png 2>/dev/null || true

  # Select it. plymouth-set-default-theme -R does update-alternatives AND the initramfs.
  # It lives in /usr/sbin, which is not on a normal user's PATH, so `have` says no
  # and we used to take the fallback path (and report the theme as "unknown").
  PSDT="$(command -v plymouth-set-default-theme 2>/dev/null || echo /usr/sbin/plymouth-set-default-theme)"
  if [ -x "$PSDT" ]; then
    sudo "$PSDT" -R w1ld0s >/dev/null 2>&1 \
      && ok "Plymouth theme set to w1ld0s (initramfs rebuilt)" \
      || warn "plymouth-set-default-theme failed"
  else
    sudo update-alternatives --install /usr/share/plymouth/themes/default.plymouth \
         default.plymouth "$THEME/w1ld0s.plymouth" 200 >/dev/null 2>&1
    sudo update-alternatives --set default.plymouth "$THEME/w1ld0s.plymouth" >/dev/null 2>&1
    sudo update-initramfs -u >/dev/null 2>&1 && ok "Plymouth theme set (initramfs rebuilt)"
  fi
else
  warn "stock spinner theme not found at $SPINNER — skipping the splash."
  warn "install 'plymouth-themes' and re-run: ./bootstrap.sh 06"
fi

# ---------------------------------------------------------------------------
# Login screen — the third stage of the boot chain the user actually sees
# ---------------------------------------------------------------------------
# Branded per the display manager module 05 left in charge, rather than assuming
# one: Ubuntu Desktop keeps gdm3 unless you deliberately switch to lightdm, and
# a greeter left stock Ubuntu-orange in the middle of a w1ld0s boot is the one
# frame that gives the game away.
GREETER_DIR=/usr/share/w1ld0s
sudo install -D -m644 "$BRAND/w1ld0s-grub.png"   "$GREETER_DIR/greeter-background.png"
# No greeter logo is installed — see the org/gnome/login-screen block below for why.
sudo rm -f "$GREETER_DIR/greeter-logo.png"

ACTIVE_DM="$(basename "$(cat /etc/X11/default-display-manager 2>/dev/null || echo unknown)")"
case "$ACTIVE_DM" in
  gdm3|gdm)
    # GDM's greeter runs as the 'gdm' user and reads a COMPILED dconf database,
    # so `gsettings set` from your account changes nothing. The packaged
    # /usr/share/gdm/dconf/00-upstream-settings documents the supported route:
    # add a higher-numbered file beside it and recompile.
    #
    # The background is the part everyone patches gnome-shell.gresource for.
    # Don't — Ubuntu ships com.ubuntu.login-screen with a background-picture-uri
    # key for exactly this, so a gnome-shell update can't silently revert us and
    # a bad edit can't leave the greeter unable to draw.
    GDM_CONF=/usr/share/gdm/dconf/95-w1ld0s
    # Captured, not piped: under `set -o pipefail` a `cmd | grep -q` condition
    # reports cmd's failure even when grep matched (see CLAUDE.md).
    GDM_SCHEMAS="$(gsettings list-schemas 2>/dev/null)"
    {
      if printf '%s\n' "$GDM_SCHEMAS" | grep -qx com.ubuntu.login-screen; then
        printf '[com/ubuntu/login-screen]\n'
        printf "background-picture-uri='file://%s/greeter-background.png'\n" "$GREETER_DIR"
        printf "background-size='cover'\n"
        printf "background-color='#000000'\n\n"
      else
        warn "no com.ubuntu.login-screen schema — greeter background left stock, styling only"
      fi
      # NO logo= key, deliberately. Two reasons, and the second one is a trap:
      #   1. greeter-background.png already carries the logo, so a second copy is
      #      redundant on a greeter we control end to end.
      #   2. GNOME 50 renders it UNSCALED. loginDialog's _updateLogoTexture now
      #      calls load_file_async(file, -1, -1, …) — no height cap, where older
      #      shells passed 48px — and _getLogoBinAllocation anchors the result at
      #      y1 = (dialog_height - image_height) * 0.96 to line the logo up with
      #      the Plymouth watermark. Ubuntu's watermark is 187x72, so upstream it
      #      sits at the bottom edge; our 480x480 splash spanned y576-y1056 on a
      #      1080p panel and drew straight over the password entry.
      # If a logo is ever wanted back, ship a separate ~72px-tall asset for it —
      # do not point this key at w1ld0s-splash.png.
      printf '[org/gnome/login-screen]\n'
      printf 'banner-message-enable=true\n'
      printf "banner-message-text='w1ld0s'\n\n"
      printf '[org/gnome/desktop/interface]\n'
      printf "color-scheme='prefer-dark'\n"
      printf "gtk-theme='Adwaita-dark'\n"
    } | sudo tee "$GDM_CONF" >/dev/null

    sudo /usr/share/gdm/generate-config >/dev/null 2>&1 \
      && ok "GDM greeter branded (dark, w1ld0s background)" \
      || warn "greeter db not recompiled — run: sudo /usr/share/gdm/generate-config"
    ;;
  lightdm)
    # lightdm-gtk-greeter is a plain INI file. Back up a hand-edited one once,
    # the same way install_asset does, so a re-run never silently eats changes.
    LG_CONF=/etc/lightdm/lightdm-gtk-greeter.conf
    if [ -f "$LG_CONF" ] && ! sudo grep -q 'w1ld0s' "$LG_CONF"; then
      sudo cp -a "$LG_CONF" "$LG_CONF.w1ld0s.bak" && warn "backed up $LG_CONF -> $LG_CONF.w1ld0s.bak"
    fi
    sudo tee "$LG_CONF" >/dev/null <<EOF
# w1ld0s greeter branding — written by modules/06-boot-branding.sh
[greeter]
background = $GREETER_DIR/greeter-background.png
theme-name = Adwaita-dark
icon-theme-name = Adwaita
font-name = Fira Code Medium 10
xft-antialias = true
indicators = ~host;~spacer;~clock;~spacer;~session;~power
EOF
    ok "lightdm greeter branded (dark, w1ld0s background)"
    ;;
  *)
    warn "unknown display manager '$ACTIVE_DM' — greeter left unbranded"
    ;;
esac

# ---------------------------------------------------------------------------
log "Current Plymouth theme: $("${PSDT:-/usr/sbin/plymouth-set-default-theme}" 2>/dev/null || echo unknown)"
cat <<'EOF'

  Verify without rebooting:
      sudo plymouthd --debug --tty=/dev/tty7 ; sudo plymouth --show-splash
      sleep 5 ; sudo plymouth --quit

  Check the splash reads OUR assets, not the stock spinner's:
      grep ImageDir /usr/share/plymouth/themes/w1ld0s/w1ld0s.plymouth

  If the machine uses an encrypted root, confirm the passphrase prompt still
  appears on the FIRST reboot before snapshotting.
EOF
ok "boot branding done."
