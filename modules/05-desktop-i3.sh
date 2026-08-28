#!/usr/bin/env bash
# 05-desktop-i3.sh — i3 window manager stack, fonts, terminator, display manager,
# VMware guest tools, GUI extras (Brave, VS Code). Imports your i3 config verbatim.
[ -n "${W1LD0S_ROOT:-}" ] || { W1LD0S_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; source "$W1LD0S_ROOT/lib/common.sh"; }

log "Installing i3 desktop stack…"
apt_install_list desktop.apt

# --- vendor apt repos for Brave + VS Code (GUI extras) ----------------------
if ! have brave-browser; then
  log "Adding Brave apt repo…"
  sudo curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg \
    https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] https://brave-browser-apt-release.s3.brave.com/ stable main" \
    | sudo tee /etc/apt/sources.list.d/brave-browser-release.list >/dev/null
  _APT_UPDATED=0; apt_install brave-browser || warn "brave install failed"
fi
if ! have code; then
  log "Adding VS Code apt repo…"
  curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /tmp/packages.microsoft.gpg
  sudo install -o root -g root -m 644 /tmp/packages.microsoft.gpg /usr/share/keyrings/packages.microsoft.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" \
    | sudo tee /etc/apt/sources.list.d/vscode.list >/dev/null
  rm -f /tmp/packages.microsoft.gpg
  _APT_UPDATED=0; apt_install code || warn "code install failed"
fi

# --- import your i3 config, i3blocks, fonts, terminator (verbatim) ----------
install_asset i3/config          "$HOME/.config/i3/config"
install_asset i3/i3blocks.conf   "$HOME/.config/i3/i3blocks.conf"
# setup_workspace (w1ld0s-tools) hardcodes this path in its append_layout call,
# so the name and the location are load-bearing rather than a convention. The
# asset shipped here but was never installed, so the layout silently never
# restored and setup_workspace had nothing to append.
install_asset i3/i3-workspace-1.json "$HOME/.config/i3/i3-workspace-1.json"
[ -d "$W1LD0S_ROOT/assets/i3/scripts" ] && { mkdir -p "$HOME/.config/i3/scripts"; cp -a "$W1LD0S_ROOT/assets/i3/scripts/." "$HOME/.config/i3/scripts/"; }
install_asset terminator/config  "$HOME/.config/terminator/config"
mkdir -p "$HOME/.fonts" && cp -a "$W1LD0S_ROOT/assets/fonts/." "$HOME/.fonts/" && fc-cache -f "$HOME/.fonts" >/dev/null 2>&1
ok "fonts installed ($(ls "$HOME/.fonts" | wc -l) files)"

# --- branding: wallpaper for i3 (feh) and GNOME (gsettings) -----------------
# The imported i3 config used to point at a Kali backgrounds path that does not
# exist on Ubuntu, so the desktop came up bare. Ship our own image instead.
WALLPAPER="$HOME/.local/share/w1ld0s/w1ld0s.png"
install_asset branding/w1ld0s.png "$WALLPAPER"

# Re-runnable helper: applies the wallpaper from inside a live desktop session.
# bootstrap.sh often runs from a tty where gsettings has no session bus to talk to.
cat > "$BIN_DIR/w1ld0s-wallpaper" <<'EOF'
#!/usr/bin/env bash
# Apply the w1ld0s wallpaper in the current desktop session (GNOME and/or i3).
W="$HOME/.local/share/w1ld0s/w1ld0s.png"
[ -f "$W" ] || { echo "missing wallpaper: $W" >&2; exit 1; }

if command -v gsettings >/dev/null 2>&1 \
   && gsettings writable org.gnome.desktop.background picture-uri >/dev/null 2>&1; then
  gsettings set org.gnome.desktop.background picture-uri      "file://$W"
  gsettings set org.gnome.desktop.background picture-uri-dark "file://$W"
  gsettings set org.gnome.desktop.background picture-options  'scaled'
  gsettings set org.gnome.desktop.background primary-color    '#000000'
  gsettings set org.gnome.desktop.screensaver picture-uri     "file://$W"
  gsettings set org.gnome.desktop.screensaver picture-options 'scaled'
  gsettings set org.gnome.desktop.screensaver primary-color   '#000000'
  echo "[+] GNOME wallpaper set"
fi

if command -v feh >/dev/null 2>&1 && [ -n "${DISPLAY:-}" ]; then
  feh --bg-max --image-bg "#000000" "$W" && echo "[+] i3/X11 wallpaper set via feh"
fi
EOF
chmod +x "$BIN_DIR/w1ld0s-wallpaper"

# Try now; harmless and expected to no-op when run headless.
if "$BIN_DIR/w1ld0s-wallpaper" >/dev/null 2>&1; then
  ok "wallpaper applied to the current session"
else
  log "wallpaper staged; no live desktop session yet — run 'w1ld0s-wallpaper' after logging in"
fi
ok "branding installed: $WALLPAPER"

# --- dark mode --------------------------------------------------------------
# i3 has no settings daemon, so GTK apps read these ini files directly. Without
# them GTK defaults to the light theme and every window comes up white.
for gtkver in 3.0 4.0; do
  mkdir -p "$HOME/.config/gtk-$gtkver"
  cat > "$HOME/.config/gtk-$gtkver/settings.ini" <<'EOF'
[Settings]
gtk-theme-name=Adwaita-dark
gtk-icon-theme-name=Adwaita
gtk-application-prefer-dark-theme=1
EOF
done
ok "GTK3/GTK4 set to Adwaita-dark"

# Qt apps (Burp is Java/Swing, but qterminal, gqrx and friends follow this).
if ! grep -q '^export QT_STYLE_OVERRIDE' "$HOME/.profile" 2>/dev/null; then
  echo 'export QT_STYLE_OVERRIDE=Adwaita-Dark' >> "$HOME/.profile"
fi

# GNOME session, when there is one — no-op under i3 or from a tty.
if have gsettings && gsettings writable org.gnome.desktop.interface color-scheme >/dev/null 2>&1; then
  gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'            2>/dev/null || true
  gsettings set org.gnome.desktop.interface gtk-theme    'Adwaita-dark'           2>/dev/null || true
  gsettings set org.gnome.desktop.interface monospace-font-name 'Fira Code Medium 10' 2>/dev/null || true
  ok "GNOME colour-scheme set to prefer-dark"
fi

# --- i3blocks-contrib (your i3blocks.conf references these scripts) ---------
[ -d "$HOME/.config/i3blocks" ] || git clone --quiet https://github.com/vivien/i3blocks-contrib "$HOME/.config/i3blocks" || warn "i3blocks-contrib clone failed"

# --- display manager and default session -------------------------------------
# Two separate settings, and the earlier version of this block only did the first
# one. Switching the display manager does NOT get the box off Wayland: the
# session type is decided by which .desktop the greeter launches, not by who
# launches it. Brave and Burp misbehave under Wayland, and on 26.04 there is no
# way to run GNOME on X11 — GNOME Shell 50 dropped X11, ubuntu-session ships only
# /usr/share/wayland-sessions/ubuntu.desktop, and neither gnome-session-xsession
# nor ubuntu-desktop-xorg exists in the archive. So the X11 desktop here is i3,
# and it has to be made the default session explicitly. Both halves are below.
#
# gdm3 is left INSTALLED, only inactive: purging it takes ubuntu-desktop with it.
# To go back: sudo dpkg-reconfigure gdm3 && ./bootstrap.sh 06
DM_FILE=/etc/X11/default-display-manager
DM_UNIT=/etc/systemd/system/display-manager.service
# -x on the absolute path, not `have lightdm`: this is the path written into
# DM_FILE, and it does not depend on /usr/sbin being on a non-root PATH.
if [ ! -x /usr/sbin/lightdm ]; then
  warn "lightdm not installed — display manager left alone. Re-run after fixing desktop.apt."
else
  if [ "$(cat "$DM_FILE" 2>/dev/null)" != "/usr/sbin/lightdm" ]; then
    log "Making lightdm the display manager (currently: $(basename "$(cat "$DM_FILE" 2>/dev/null || echo none)"))…"
    # Preseed first so a later dpkg-reconfigure of any DM agrees with us. This
    # used to carry 2>/dev/null, which hid whatever went wrong here.
    echo "lightdm shared/default-x-display-manager select lightdm" | sudo debconf-set-selections \
      || warn "debconf-set-selections failed — a later dpkg-reconfigure may undo the switch"
    sudo DEBIAN_FRONTEND=noninteractive dpkg-reconfigure lightdm >/dev/null 2>&1 \
      || warn "dpkg-reconfigure lightdm failed"
  fi
  # Assert, do not trust. On a real build the reconfigure above left DM_FILE
  # untouched under DEBIAN_FRONTEND=noninteractive, module 06 read gdm3 from it
  # two minutes later and branded the wrong greeter, and the only sign was one
  # warn in the scroll. Write the two things that actually decide what boots.
  if [ "$(cat "$DM_FILE" 2>/dev/null)" != "/usr/sbin/lightdm" ]; then
    warn "$DM_FILE still reads '$(cat "$DM_FILE" 2>/dev/null || echo unset)' — writing it directly"
    echo /usr/sbin/lightdm | sudo tee "$DM_FILE" >/dev/null
  fi
  # DM_FILE is debconf's record; this symlink is what systemd boots, and they can
  # disagree. `systemctl enable lightdm` refuses to replace an existing
  # display-manager.service alias ("file already exists") — -f is what takes it.
  if [ "$(basename "$(readlink -f "$DM_UNIT" 2>/dev/null || echo none)")" != "lightdm.service" ]; then
    sudo systemctl enable -f lightdm.service >/dev/null 2>&1
    [ "$(basename "$(readlink -f "$DM_UNIT" 2>/dev/null || echo none)")" = "lightdm.service" ] \
      || warn "$DM_UNIT still points at $(basename "$(readlink -f "$DM_UNIT" 2>/dev/null || echo nothing)") — gdm3 may still start"
  fi
  # Default session: i3, so the first login after provisioning lands on X11
  # instead of the Ubuntu GNOME session, which is Wayland. It sets the default,
  # not a restriction — GNOME stays in the greeter's session picker.
  #
  # LightDM reads /usr/share/lightdm/lightdm.conf.d/*.conf, then
  # /etc/lightdm/lightdm.conf.d/*.conf, then /etc/lightdm/lightdm.conf, last
  # value winning. Debian's 01_ and Ubuntu's 02_ drop-ins live in the FIRST of
  # those, a whole directory below this one, so the 90- prefix is not what beats
  # them — it only orders us against other drop-ins in the same directory. What
  # a drop-in cannot outrank is lightdm.conf itself, so say so rather than write
  # a file that looks right and loses.
  LDM_SESSION_CONF=/etc/lightdm/lightdm.conf.d/90-w1ld0s-session.conf
  if ! grep -qx 'user-session=i3' "$LDM_SESSION_CONF" 2>/dev/null; then
    sudo install -d -m755 /etc/lightdm/lightdm.conf.d
    printf '[Seat:*]\nuser-session=i3\n' | sudo tee "$LDM_SESSION_CONF" >/dev/null \
      && ok "default session set to i3 ($LDM_SESSION_CONF)"
  fi
  LDM_OVERRIDE="$(grep -E '^[[:space:]]*user-session[[:space:]]*=' /etc/lightdm/lightdm.conf 2>/dev/null \
                  | tail -n1 | cut -d= -f2- | tr -d '[:space:]')"
  if [ -n "$LDM_OVERRIDE" ] && [ "$LDM_OVERRIDE" != i3 ]; then
    warn "/etc/lightdm/lightdm.conf sets user-session=$LDM_OVERRIDE — it is read after $LDM_SESSION_CONF and wins; remove that line or the greeter still defaults to $LDM_OVERRIDE"
  fi
fi
ACTIVE_DM="$(basename "$(cat "$DM_FILE" 2>/dev/null || echo unknown)")"
[ "$ACTIVE_DM" = "lightdm" ] || warn "display manager is '$ACTIVE_DM', expected lightdm"
sudo systemctl enable --now vmtoolsd >/dev/null 2>&1 || true

# Module 06 brands whichever DM is in charge here, so say which one that is.
ok "i3 desktop ready. i3 is the default session at the $ACTIVE_DM login screen (log out first)."
