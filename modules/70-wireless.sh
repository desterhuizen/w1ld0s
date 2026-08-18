#!/usr/bin/env bash
# 70-wireless.sh — Wireless / SDR / Bluetooth tooling. On a VM these only work
# with USB passthrough of a real adapter; the module installs the tooling anyway.
[ -n "${W1LD0S_ROOT:-}" ] || { W1LD0S_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; source "$W1LD0S_ROOT/lib/common.sh"; }

# --- native wireless / bluetooth / sdr packages -----------------------------
# 'wireless-tools' (iwconfig et al) was dropped from the archive — superseded by
# 'iw', already listed. Its absence used to abort this whole batch, taking the
# hcxtools build deps with it while the module still reported success.
apt_install \
  aircrack-ng reaver bully cowpatty mdk4 \
  bluez bluez-tools \
  rfkill iw \
  rtl-sdr hackrf gqrx-sdr \
  libpcap-dev pkg-config libssl-dev libcurl4-openssl-dev

# --- hcxtools + hcxdumptool (Kali long-tail, build from source) -------------
if ! have hcxpcapngtool; then
  clone_or_pull https://github.com/ZerBea/hcxtools.git "$TOOLS_DIR/hcxtools"
  ( cd "$TOOLS_DIR/hcxtools" && make -s && sudo make install ) || warn "hcxtools build failed"
fi
if ! have hcxdumptool; then
  clone_or_pull https://github.com/ZerBea/hcxdumptool.git "$TOOLS_DIR/hcxdumptool"
  ( cd "$TOOLS_DIR/hcxdumptool" && make -s && sudo make install ) || warn "hcxdumptool build failed"
fi

warn "Wireless/SDR/BT tools are installed but a VM has NO radios by default."
warn "Attach a USB Wi-Fi/BT/SDR adapter to the VM (USB passthrough) to use them."
ok "wireless toolkit installed."
