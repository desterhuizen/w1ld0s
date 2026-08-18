#!/usr/bin/env bash
# 07-gnome-shell.sh — make the GNOME session look deliberate instead of stock:
#   * dock: minimal favourites, bottom, autohiding
#   * app grid: CLI/duplicate entries hidden, GUI pentest tools in one folder
#   * extensions: desktop icons and the snap/web search providers switched off
#
# Ubuntu 26.04 ships GNOME 50 on Wayland under gdm3. i3 (module 05) is a session
# you pick at the greeter, so both stacks coexist — nothing here affects i3.
#
# WHAT LIVES WHERE: the *session* settings all go through gsettings, which needs
# a live session bus. bootstrap.sh usually runs from a tty where there is none,
# so this module GENERATES ~/.local/bin/w1ld0s-gnome and runs it once; re-run
# that by hand from inside GNOME if it no-ops here. Same pattern as
# w1ld0s-wallpaper in module 05, for the same reason. The *filesystem* side
# (.desktop overrides) has no such constraint and is applied directly.
[ -n "${W1LD0S_ROOT:-}" ] || { W1LD0S_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; source "$W1LD0S_ROOT/lib/common.sh"; }

if ! have gsettings; then
  warn "gsettings not installed — no GNOME here; skipping shell cleanup"
  return 0 2>/dev/null || exit 0
fi

APPS_DIR="$HOME/.local/share/applications"
mkdir -p "$APPS_DIR"

# ---------------------------------------------------------------------------
# App grid: hide the noise
# ---------------------------------------------------------------------------
# A user .desktop shadows the system one of the same name, so this hides without
# deleting anything and survives `apt-get install --reinstall`.
set_nodisplay() {  # set_nodisplay <desktop-file> ; returns 1 if already hidden
  local f="$1"
  grep -q '^NoDisplay=true' "$f" 2>/dev/null && return 1
  if have desktop-file-edit; then
    desktop-file-edit --set-key=NoDisplay --set-value=true "$f" 2>/dev/null && return 0
    warn "desktop-file-edit failed on $(basename "$f") — falling back to sed"
  fi
  if grep -q '^NoDisplay=' "$f" 2>/dev/null; then
    sed -i 's|^NoDisplay=.*|NoDisplay=true|' "$f"
  else
    sed -i '0,/^\[Desktop Entry\]/s//[Desktop Entry]\nNoDisplay=true/' "$f"
  fi
}

hidden=0 skipped=0
while IFS= read -r id; do
  src="/usr/share/applications/$id.desktop"
  dst="$APPS_DIR/$id.desktop"
  # Not installed on this box — the list is shared across builds, so that is fine.
  [ -f "$src" ] || { skipped=$((skipped + 1)); continue; }
  if [ -f "$dst" ] && grep -q '^NoDisplay=true' "$dst"; then continue; fi
  cp -a "$src" "$dst" && chmod u+w "$dst"
  set_nodisplay "$dst" && hidden=$((hidden + 1))
done < <(read_list gnome.hide)
ok "app grid: $hidden entries hidden ($skipped listed but not installed)"

# ---------------------------------------------------------------------------
# Launchers for the GUI tools that ship none we can name
# ---------------------------------------------------------------------------
# Burp: install4j names its entry install4j_<random>-BurpSuiteCommunity.desktop,
# so the id differs per box and cannot be referenced from gnome.folder/gnome.hide.
# Ghidra: module 50 only creates a PATH shim, so it never reaches the app grid.
# Both are generated rather than shipped under assets/ because the Exec path has
# to follow $OPT_DIR.
gen_launcher() {  # gen_launcher <id> <name> <comment> <exec> <icon> [extra-lines]
  local id="$1" name="$2" comment="$3" exec_="$4" icon="$5" extra="${6:-}"
  {
    printf '[Desktop Entry]\n'
    printf '# Written by modules/07-gnome-shell.sh — edit that, not this file.\n'
    printf 'Type=Application\nName=%s\nComment=%s\n' "$name" "$comment"
    printf 'Exec="%s" %%U\nIcon=%s\n' "$exec_" "$icon"
    printf 'Categories=Development;Security;\nTerminal=false\n'
    [ -z "$extra" ] || printf '%s\n' "$extra"
  } > "$APPS_DIR/$id.desktop"
  chmod 644 "$APPS_DIR/$id.desktop"
  ok "app grid: $id.desktop"
}

BURP_HOME="$OPT_DIR/BurpSuiteCommunity"
if [ -x "$BURP_HOME/BurpSuiteCommunity" ]; then
  gen_launcher w1ld0s-burpsuite "Burp Suite Community" "Web proxy / scanner" \
    "$BURP_HOME/BurpSuiteCommunity" "$BURP_HOME/.install4j/BurpSuiteCommunity.png" \
    "MimeType=application/x-extension-burp;x-scheme-handler/burp;
StartupWMClass=install4j-burp-StartBurp"
  # Hide install4j's own entry so the grid does not show Burp twice.
  for f in "$APPS_DIR"/install4j_*BurpSuite*.desktop; do
    [ -e "$f" ] || continue
    chmod u+w "$f"
    if set_nodisplay "$f"; then log "hid duplicate install4j entry: $(basename "$f")"; fi
  done
fi

if [ -x "$OPT_DIR/ghidra/ghidraRun" ]; then
  gen_launcher w1ld0s-ghidra "Ghidra" "SRE / decompiler" \
    "$OPT_DIR/ghidra/ghidraRun" "$OPT_DIR/ghidra/support/ghidra.ico"
fi

have update-desktop-database && update-desktop-database "$APPS_DIR" >/dev/null 2>&1

# ---------------------------------------------------------------------------
# Ptyxis — GNOME's terminal, styled to match terminator
# ---------------------------------------------------------------------------
# Module 05 imports assets/terminator/config, but under GNOME the terminal you
# actually get is Ptyxis, which keeps everything in dconf and reads custom
# palettes as keyfiles from this directory. The file has to land before the
# gsettings below name it, or Ptyxis silently falls back to the built-in list.
PTYXIS_PALETTES="$HOME/.local/share/org.gnome.Ptyxis/palettes"
if have ptyxis; then
  install_asset ptyxis/w1ld0s.palette "$PTYXIS_PALETTES/w1ld0s.palette"
fi

# ---------------------------------------------------------------------------
# Session settings — generated, so they can be re-applied from inside GNOME
# ---------------------------------------------------------------------------
mapfile -t FAV_IDS    < <(read_list gnome.favorites)
mapfile -t FOLDER_IDS < <(read_list gnome.folder)

{
  printf '#!/usr/bin/env bash\n'
  printf '# w1ld0s GNOME shell settings — generated by modules/07-gnome-shell.sh.\n'
  printf '# Re-run from inside a GNOME session; edit tools.d/gnome.* and re-run\n'
  printf '# "./bootstrap.sh 07" to change what it applies.\n'
  printf 'set -uo pipefail\n\n'
  printf 'FAVORITES=(%s)\n'   "$(printf '%q ' "${FAV_IDS[@]+"${FAV_IDS[@]}"}")"
  printf 'FOLDER_APPS=(%s)\n' "$(printf '%q ' "${FOLDER_IDS[@]+"${FOLDER_IDS[@]}"}")"
  cat <<'EOF'

gsettings writable org.gnome.shell favorite-apps >/dev/null 2>&1 || {
  echo "[!] no live GNOME session bus — run w1ld0s-gnome from inside your GNOME session" >&2
  exit 1
}

app_exists() { [ -f "/usr/share/applications/$1" ] || [ -f "$HOME/.local/share/applications/$1" ]; }

# Render ids as a GVariant string array: a b -> ['a', 'b']
gv_list() {
  local out="" id
  for id in "$@"; do out="$out'$id', "; done
  printf '[%s]' "${out%, }"
}

# --- dock contents ---------------------------------------------------------
# Filtered against what is actually installed: one uninstalled tool must not
# blank the whole dock.
sel=()
for a in "${FAVORITES[@]+"${FAVORITES[@]}"}"; do app_exists "$a" && sel+=("$a"); done
if [ "${#sel[@]}" -gt 0 ]; then
  gsettings set org.gnome.shell favorite-apps "$(gv_list "${sel[@]}")"
  echo "[+] dock: ${#sel[@]} favourites pinned"
else
  echo "[!] dock: none of the favourites are installed — leaving it alone" >&2
fi

# --- dock behaviour --------------------------------------------------------
# ubuntu-dock reads dash-to-dock's schema. dock-fixed is the one that matters:
# autohide/intellihide are already true out of the box but dock-fixed=true
# overrides both, which is why the stock dock never actually hides.
DOCK=org.gnome.shell.extensions.dash-to-dock
if gsettings writable "$DOCK" dock-position >/dev/null 2>&1; then
  gsettings set "$DOCK" dock-position       'BOTTOM'
  gsettings set "$DOCK" dock-fixed          false
  gsettings set "$DOCK" autohide            true
  gsettings set "$DOCK" intellihide         true
  gsettings set "$DOCK" extend-height       false
  gsettings set "$DOCK" dash-max-icon-size  32
  gsettings set "$DOCK" show-trash          false
  gsettings set "$DOCK" show-mounts         false
  echo "[+] dock: bottom, autohiding, 32px icons"
else
  echo "[*] dash-to-dock schema absent (no ubuntu-dock) — skipping dock layout"
fi

# --- extensions ------------------------------------------------------------
# DISABLED-extensions, not enabled-extensions. Ubuntu enables these seven from
# the session mode file /usr/share/gnome-shell/modes/ubuntu.json, so
# `gsettings get org.gnome.shell enabled-extensions` reads @as [] and removing
# from it does nothing at all. Blocking by name here is the only route.
# snapd-prompting stays ON on purpose — that is the snap permission prompt.
gsettings set org.gnome.shell disabled-extensions \
  "['ding@rastersoft.com', 'snapd-search-provider@canonical.com', 'web-search-provider@ubuntu.com']"
echo "[+] extensions: desktop icons + snap/web search providers disabled"

# --- app-grid folder -------------------------------------------------------
FOLDER=w1ld0s
FPATH="org.gnome.desktop.app-folders.folder:/org/gnome/desktop/app-folders/folders/$FOLDER/"

# Read-modify-write: Ubuntu already ships System/Utilities/YaST/Pardus here and
# an empty value prints as "@as []", which no naive sed append survives.
kids=()
while IFS= read -r k; do [ -n "$k" ] && kids+=("$k"); done < <(
  gsettings get org.gnome.desktop.app-folders folder-children | grep -o "'[^']*'" | tr -d "'"
)
present=0
for k in "${kids[@]+"${kids[@]}"}"; do [ "$k" = "$FOLDER" ] && present=1; done
[ "$present" -eq 1 ] || kids+=("$FOLDER")
gsettings set org.gnome.desktop.app-folders folder-children "$(gv_list "${kids[@]}")"

fsel=()
for a in "${FOLDER_APPS[@]+"${FOLDER_APPS[@]}"}"; do app_exists "$a" && fsel+=("$a"); done
gsettings set "$FPATH" name "$FOLDER"
gsettings set "$FPATH" translate false
gsettings set "$FPATH" apps "$(gv_list "${fsel[@]+"${fsel[@]}"}")"
echo "[+] app grid: '$FOLDER' folder with ${#fsel[@]} tools"

# --- ptyxis ----------------------------------------------------------------
# GNOME's terminal. Settings mirror assets/terminator/config: same palette,
# same Fira Code, same 0.9 opacity, no scrollbar, unlimited scrollback.
PTY=org.gnome.Ptyxis
if gsettings writable "$PTY" font-name >/dev/null 2>&1; then
  gsettings set "$PTY" use-system-font   false
  gsettings set "$PTY" font-name         'Fira Code Medium 10'
  gsettings set "$PTY" interface-style   'dark'
  gsettings set "$PTY" scrollbar-policy  'never'
  gsettings set "$PTY" audible-bell      false

  # Every profile, not just the default one — a second profile styled like
  # stock Ubuntu is exactly the frame that gives the game away on a screenshot.
  if [ -f "$HOME/.local/share/org.gnome.Ptyxis/palettes/w1ld0s.palette" ]; then
    while IFS= read -r uuid; do
      [ -n "$uuid" ] || continue
      P="org.gnome.Ptyxis.Profile:/org/gnome/Ptyxis/Profiles/$uuid/"
      gsettings set "$P" palette          'w1ld0s'
      gsettings set "$P" opacity          0.9
      gsettings set "$P" limit-scrollback false
    done < <(gsettings get "$PTY" profile-uuids | grep -o "'[^']*'" | tr -d "'")
    echo "[+] ptyxis: w1ld0s palette, Fira Code, 0.9 opacity"
  else
    echo "[!] ptyxis: w1ld0s.palette not installed — run './bootstrap.sh 07'" >&2
  fi
fi

echo "[*] app-grid changes need a shell restart. On Wayland that means log out"
echo "    and back in — Alt+F2 'r' is X11-only. Ptyxis reads palette files at"
echo "    startup, so close every open window before checking its colours."
EOF
} > "$BIN_DIR/w1ld0s-gnome"
chmod +x "$BIN_DIR/w1ld0s-gnome"
ok "generated $BIN_DIR/w1ld0s-gnome"

# Try now; expected to no-op from a tty, exactly like w1ld0s-wallpaper.
if "$BIN_DIR/w1ld0s-gnome" >/dev/null 2>&1; then
  ok "GNOME shell settings applied to the current session"
else
  log "GNOME settings staged; no live session bus — run 'w1ld0s-gnome' after logging in"
fi

ok "GNOME shell cleanup done."
