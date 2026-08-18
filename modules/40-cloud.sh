#!/usr/bin/env bash
# 40-cloud.sh — Cloud pentest toolkit: aws/az/gcloud/kubectl CLIs + pipx tools.
[ -n "${W1LD0S_ROOT:-}" ] || { W1LD0S_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; source "$W1LD0S_ROOT/lib/common.sh"; }

arch="$(dpkg --print-architecture)"   # amd64 | arm64

# --- AWS CLI v2 (official installer) ----------------------------------------
if ! have aws; then
  log "Installing AWS CLI v2…"
  case "$arch" in
    amd64) awszip="awscli-exe-linux-x86_64.zip" ;;
    arm64) awszip="awscli-exe-linux-aarch64.zip" ;;
  esac
  curl -fsSL "https://awscli.amazonaws.com/$awszip" -o "$HOME/.local/tmp/awscliv2.zip" \
    && unzip -q -o "$HOME/.local/tmp/awscliv2.zip" -d "$HOME/.local/tmp" \
    && sudo "$HOME/.local/tmp/aws/install" --update || warn "aws cli install failed"
fi

# --- Azure CLI (Microsoft repo) ---------------------------------------------
if ! have az; then
  log "Installing Azure CLI…"
  curl -fsSL https://aka.ms/InstallAzureCLIDeb | sudo bash || warn "az install failed"
fi

# --- gcloud (Google repo) ----------------------------------------------------
if ! have gcloud; then
  log "Installing gcloud SDK…"
  curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
  echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
    | sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list >/dev/null
  _APT_UPDATED=0; apt_install google-cloud-cli || warn "gcloud install failed"
fi

# --- kubectl (release binary) -----------------------------------------------
if ! have kubectl; then
  log "Installing kubectl…"
  kver="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
  curl -fsSL "https://dl.k8s.io/release/${kver}/bin/linux/${arch}/kubectl" -o "$HOME/.local/tmp/kubectl" \
    && install -m755 "$HOME/.local/tmp/kubectl" "$BIN_DIR/kubectl" || warn "kubectl install failed"
fi

# --- pipx cloud tools -------------------------------------------------------
log "Installing cloud pipx tools…"
pipx_install_list cloud.pipx

# --- trufflehog (release binary) --------------------------------------------
if ! have trufflehog; then
  # was "${arch/...}" — $arch leaked in from module 00 and only worked when the
  # whole run happened in one shell. @ARCH_ALT@ is resolved by gh_release.
  if gh_release trufflesecurity/trufflehog@v3.97.0 "trufflehog.*linux.*@ARCH_ALT@.*tar\.gz$" "$HOME/.local/tmp/trufflehog.tar.gz"; then
    tar -xzf "$HOME/.local/tmp/trufflehog.tar.gz" -C "$HOME/.local/tmp" trufflehog 2>/dev/null \
      && install -m755 "$HOME/.local/tmp/trufflehog" "$BIN_DIR/trufflehog" && ok "trufflehog installed"
  fi
fi

ok "cloud toolkit installed."
