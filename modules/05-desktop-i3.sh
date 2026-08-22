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

# --- VMware RDP keymap fix ---------------------------------------------------
# Only applied if not already present in the i3 config.
if [ -f "$HOME/.config/i3/config" ] && ! grep -q "keycode 94 = grave" "$HOME/.config/i3/config"; then
  log "Appending VMware RDP xmodmap keymap fixes to i3 config…"
  cat >> "$HOME/.config/i3/config" <<'EOF'

# --- w1ld0s: VMware RDP keymap fixes ---
exec_always --no-startup-id xmodmap -e "keycode 94 = grave asciitilde"
exec_always --no-startup-id xmodmap -e "keycode 51 = backslash bar backslash bar"
exec_always --no-startup-id xmodmap -e "keycode 49 = numbersign asciitilde"
exec_always --no-startup-id xmodmap -e "keycode 11 = 2 at 2 at"
exec_always --no-startup-id xmodmap -e "keycode 48 = apostrophe quotedbl apostrophe quotedbl"
exec_always --no-startup-id xmodmap -e "keycode 21 = section plusminus"
EOF
fi

# --- display manager ---------------------------------------------------------
# lightdm, not gdm3. gdm3 gives every session it starts a Wayland environment,
# and on staging that broke the two GUI tools this box exists for: Chromium and
# Burp Suite both misbehaved. The fix everyone reaches for first — WaylandEnable=false
# in /etc/gdm3/custom.conf — is dead here, because Ubuntu 26.04 ships no Xorg
# GNOME session and so leaves nothing to log into. lightdm starts an X11 seat and
# still lists the GNOME Wayland session, which was confirmed to launch, so the
# switch costs nothing.
#
# gdm3 is left INSTALLED, only inactive: purging it takes ubuntu-desktop with it.
# To go back: sudo dpkg-reconfigure gdm3
#
# Ubuntu Desktop owns /etc/systemd/system/display-manager.service, so a bare
# `systemctl enable lightdm` fails ("file already exists") and leaves gdm3 in
# charge anyway. Switching DMs is a debconf question, not a unit toggle.
DM_FILE=/etc/X11/default-display-manager
# -x on the absolute path, not `have lightdm`: this is the path written into
# DM_FILE, and it does not depend on /usr/sbin being on a non-root PATH.
if [ ! -x /usr/sbin/lightdm ]; then
  warn "lightdm not installed — display manager left alone. Re-run after fixing desktop.apt."
elif [ "$(cat "$DM_FILE" 2>/dev/null)" != "/usr/sbin/lightdm" ]; then
  log "Making lightdm the display manager (currently: $(basename "$(cat "$DM_FILE" 2>/dev/null || echo none)"))…"
  echo "lightdm shared/default-x-display-manager select lightdm" | sudo debconf-set-selections 2>/dev/null
  sudo DEBIAN_FRONTEND=noninteractive dpkg-reconfigure lightdm >/dev/null 2>&1 \
    || warn "dpkg-reconfigure lightdm failed — switch by hand: sudo dpkg-reconfigure lightdm"
fi
ACTIVE_DM="$(basename "$(cat "$DM_FILE" 2>/dev/null || echo unknown)")"
[ "$ACTIVE_DM" = "lightdm" ] || warn "display manager is '$ACTIVE_DM', expected lightdm"
sudo systemctl enable --now vmtoolsd >/dev/null 2>&1 || true

# Module 06 brands whichever DM is in charge here, so say which one that is.
ok "i3 desktop ready. Pick the i3 session at the $ACTIVE_DM login screen (log out first)."
