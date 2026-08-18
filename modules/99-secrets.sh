#!/usr/bin/env bash
# 99-secrets.sh — NON-automated. Prints a checklist of secrets/state to migrate
# from your old box over a secure channel. w1ld0s never commits or fetches these.
[ -n "${W1LD0S_ROOT:-}" ] || { W1LD0S_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; source "$W1LD0S_ROOT/lib/common.sh"; }

hr() { printf '\033[1;35m%s\033[0m\n' "────────────────────────────────────────────────────────"; }

hr
printf '\033[1;35m  SECRETS / STATE TO MIGRATE (manual, secure channel only)\033[0m\n'
hr
cat <<'EOF'
Copy these from the old host with scp/rsync-over-ssh or a USB vault — never git.

  [!] SSH key           DO NOT COPY ONE HERE.
        -> Module 90 generates a fresh ed25519 key on this workstation and walks
           you through adding it to GitHub. One key per box: if this VM is lost
           you revoke a single key instead of rotating one shared across hosts.
  [ ] GitHub auth       run:  gh auth login
        -> Authenticate fresh. Copying ~/.config/gh/hosts.yml moves a live oauth
           token between machines; log in on this box instead.
  [ ] OSINT API keys    ~/.config/uncover/provider-config.yaml   (18 keys: shodan/censys/fofa/…)
  [ ] NetExec config    ~/.nxc/nxc.conf
        -> keep [BloodHound-CE] pointing at your SEPARATE BloodHound host.
  [ ] Other tool state  ~/.recon-ng  ~/.wpscan  ~/.maigret  ~/.sstimap  (optional)

  VPN profiles (.ovpn): live on the /mnt/hacking mount — re-attach the mount and
  they follow. fstab line (VMware):
        vmhgfs-fuse   /mnt/   fuse   defaults,allow_other   0   0

After copying the items above:
        gh auth login            # fresh GitHub auth on this box
        ./bootstrap.sh 90        # generates the SSH key, adds it to GitHub, clones
EOF
hr

# Quick presence check so you can see what's still missing.
check() { if [ -e "$2" ]; then ok "present: $1 ($2)"; else warn "MISSING: $1 ($2)"; fi; }
check "SSH key (made by module 90)" "$HOME/.ssh/id_ed25519"
check "gh auth"        "$HOME/.config/gh/hosts.yml"
check "uncover keys"   "$HOME/.config/uncover/provider-config.yaml"
check "nxc.conf"       "$HOME/.nxc/nxc.conf"

warn "This module intentionally installs nothing. Migrate the items above by hand."
