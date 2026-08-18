<p align="center">
  <img src="../assets/branding/w1ld0s.png" alt="w1ld0s" width="320">
</p>

<h1 align="center">w1ld0s</h1>

<p align="center"><em>Stability. Trust. Dominance.</em></p>

A clean Ubuntu 26.04 LTS pentest workstation, provisioned by one idempotent bash script. No Kali coupling, no apt-versioned Python security tools, every Python CLI in its own venv.

## Why this exists

Large deployments make decisions on application versioning for you out of the box, then either you have to fix issues, update or replace tools again. 

w1ls0s attempts to keep the majority of tools in a stable working condition.

## Core principles

1. **apt = OS and stable native tools only** — compilers, libs, `nmap`, `tcpdump`, `smbclient`, JDK, i3. Never apt-install a Python security tool.
2. **Every Python CLI tool gets its own pipx venv.** `netexec` can never drag a conflicting `bloodhound` into another tool.
3. **Toolkits needing patched dependencies get a dedicated venv** under `/opt/w1ld0s/venvs`. The BloodHound-CE ingestor is pinned to a sign/seal-capable `ldap3`.
4. **Pin after the first green build.** First run is unpinned to get working fast; freeze versions into `tools.d/*` once the VM is verified.
5. **Idempotent and modular.** Every module re-runnable and independently invocable. Fix-forward is expected.
6. **You own `/opt/w1ld0s`** (venvs, ghidra, burp, wordlists) and `~/tools` (repos and binaries, kept for alias compatibility).
7. **Secrets never enter git.** `.gitignore` enforces it; `modules/99` migrates them over a secure channel.
8. **The OS and the toolkit are separate repos.** This repo provisions the box; [w1ld0s-tools](https://github.com/desterhuizen/w1ld0s-tools) holds the operator scripts and the aliases that drive them. The OS changes every two years, those scripts change every week. Nothing here depends on a private repo — a clone with no SSH key and no GitHub account provisions completely.

## Layout

```
bootstrap.sh          runs modules in order; accepts a subset by name; primes sudo
lib/common.sh         log/ok/die, have(), apt_install(), pipx_tool(), venv_create(),
                      gh_release(), shim(), clone_or_pull(), read_list(), install_asset()
modules/              the 16 provisioning steps (below)
tools.d/              editable, pinnable manifests consumed by the modules
tools.d/tools.git     the companion toolkit repo; tools.d/private.git (gitignored,
                      absent by default) is the optional private overlay
assets/               dotfiles imported verbatim: zshrc, tmux.conf, i3/, fonts/,
                      terminator/, ptyxis/ (the GNOME terminal's palette keyfile)
assets/branding/      w1ld0s.png (logo + wallpaper), w1ld0s-grub.png (1920x1080
                      GRUB background), w1ld0s-splash.png (Plymouth watermark)
docs/                 this file + the AD collection cheatsheet
```

Paths set in `lib/common.sh`: `OPT_DIR=/opt/w1ld0s`, `VENV_DIR=$OPT_DIR/venvs`, `TOOLS_DIR=$OPT_DIR/tools`, `WORDLISTS_DIR=$OPT_DIR/wordlists`, `BIN_DIR=~/.local/bin`, `REPOS_DIR=~/tools/repos`, `BINARIES_DIR=~/tools/binaries`.

## Usage

```bash
./bootstrap.sh              # everything, in order
./bootstrap.sh 20 30        # only modules starting 20 and 30
./bootstrap.sh 20-ad-network
```

Run as your normal user, not root — `lib/common.sh` refuses root and calls `sudo` only where needed. Modules that fail warn and continue rather than aborting the run.

### Desktop: GNOME or i3

Both stacks are installed and they coexist. **i3 is a session you pick at the greeter, not a display manager choice** — gdm3 lists `i3` next to the GNOME session, so nothing needs switching. Ubuntu 26.04 ships no Xorg GNOME session, so removing gdm3 would take GNOME-on-Wayland with it; module 05 therefore leaves the display manager alone by default and module 07 tidies the GNOME shell. To run lightdm instead:

```bash
W1LD0S_DM=lightdm ./bootstrap.sh 05 06     # 06 then brands lightdm's greeter
```

Session settings need a live D-Bus session bus, which `bootstrap.sh` usually does not have when run from a tty. Modules 05 and 07 therefore generate `w1ld0s-wallpaper` and `w1ld0s-gnome` in `~/.local/bin` and try them once — re-run either from inside your desktop session if it reported nothing applied.

## Modules

| Module | What it does |
| --- | --- |
| `00-base` | `base.apt`, Go 1.24.5 to `/usr/local/go`, rustup, pipx, oh-my-zsh, **zsh as the login shell** (`sudo chsh`, `usermod` fallback, result checked against `/etc/passwd`), tmux.conf + TPM, the `~/.zshrc` w1ld0s block (PATH, `$EDITOR`, `$ROCKYOU`, bash-identical colours, aliases sourcing), gunzips rockyou in place |
| `05-desktop-i3` | `desktop.apt`, Brave + VS Code vendor repos, imports i3 config/i3blocks/fonts/terminator, i3blocks-contrib, VMware RDP xmodmap fixes. Leaves the display manager alone unless `W1LD0S_DM=lightdm` (see below) |
| `06-boot-branding` | GRUB menu background, the Plymouth boot splash and the **login greeter**, all using the w1ld0s logo. Clones Ubuntu's stock `spinner` theme and swaps only the watermark, so the tested LUKS passphrase prompt is preserved. Rewrites `/etc/default/grub` (including `GRUB_TIMEOUT_STYLE=menu`, without which the background never draws) and the initramfs; brands whichever DM is active (gdm3 via `/usr/share/gdm/dconf/95-w1ld0s`, lightdm via its greeter conf) |
| `07-gnome-shell` | GNOME session cleanup from `tools.d/gnome.*`: minimal dock favourites, dock to the bottom and autohiding, CLI/duplicate entries hidden from the app grid, GUI pentest tools grouped into a `w1ld0s` folder, desktop icons and the snap/web search providers disabled. Also styles **Ptyxis** (GNOME's terminal) to match terminator — same gruvbox palette, Fira Code, 0.9 opacity. Generates `w1ld0s-gnome`; no-ops on a box with no GNOME |
| `10-python-isolation` | Ensures pipx and the shared venv dir; prints and records the isolation policy |
| `20-ad-network` | `ad.pipx`, kerbrute, Responder, krbrelayx, kerberoast, crowbar, evil-winrm, **BloodHound-CE ingestor in a dedicated venv with sign-capable ldap3** |
| `30-web` | `web.go` + nuclei templates, feroxbuster, sqlmap, joomscan, whatweb (+ its `addressable` gem), `web.pipx`, wpscan, Burp Suite Community (unattended installer) |
| `35-webserver` | nginx as a **quiet static file host** for `/var/www/html`: no `Server`/`Date`/`Last-Modified`/`ETag`, no default page, no directory listing, every non-file a bodyless 404. Config from `assets/nginx/w1ld0s.conf`; validates with `nginx -t` before touching the service and unhooks itself if that fails |
| `40-cloud` | AWS CLI v2, Azure CLI, gcloud, kubectl, `cloud.pipx`, trufflehog |
| `50-re-binary` | gdb/radare2/binwalk/checksec/ltrace/strace/patchelf, pwndbg (+uv), `re.pipx`, Ghidra, apktool/jadx/dex2jar |
| `60-payload-dev` | mingw-w64 cross-compile + wine + mono, garble, SharpCollection, ysoserial jar, DotNetToJScript, RunasCs, mimikatz, BeEF |
| `70-wireless` | aircrack-ng/reaver/bully/cowpatty/mdk4, bluez, rtl-sdr/hackrf/gqrx, hcxtools + hcxdumptool from source |
| `80-repos-binaries` | Clones `repos.git`, fetches the binary rows of `releases.gh`, Sysinternals Suite, putty-tools |
| `90-tools` | Generates this box's ed25519 key, clones [w1ld0s-tools](https://github.com/desterhuizen/w1ld0s-tools) from `tools.d/tools.git` over https, runs its `setup_links`, builds reverse_ssh and authorises the key, seeds `target`/`attack` state |
| `95-private` | Optional overlay. No-op unless you create `tools.d/private.git` (gitignored) with clone URLs for repos that can't be public; only then does it register your key with GitHub and clone them |
| `99-secrets` | Installs nothing. Prints the migration checklist and reports which secrets are present or missing |

## Tool inventory

**Native (apt)** — build-essential, git, curl, wget, jq, unzip, p7zip, ripgrep, fd-find, bat, fzf, tmux, zsh, neovim, xxd, xclip, rlwrap, socat, proxychains4, net-tools, iproute2, dnsutils, whois, tcpdump, nmap, masscan, netcat-openbsd, smbclient, cifs-utils, nfs-common, ldap-utils, openvpn, wireguard-tools, hashcat, hydra, john, gcc/g++-multilib, libc6-dev-i386, libssl-dev, libffi-dev, ruby, npm, python3 + venv/dev/pip, pipx, openjdk-21-jdk, seclists, wordlists.

**Desktop** — i3, i3status, i3blocks, i3lock, dmenu (suckless-tools), rofi, picom, feh, dunst, lightdm, xorg, network-manager(-gnome), terminator, meld, arandr, autorandr, flameshot, maim, brightnessctl, pavucontrol, xdotool, desktop-file-utils, Font Awesome + Noto, open-vm-tools(-desktop), Brave, VS Code. Two terminals, configured to look identical: terminator (i3, `assets/terminator/config`) and Ptyxis (GNOME, dconf + `assets/ptyxis/w1ld0s.palette`). Plus two generated helpers in `~/.local/bin`: `w1ld0s-wallpaper` and `w1ld0s-gnome`. *(nitrogen was dropped — not in the 26.04 archive; feh covers it.)*

**AD / network** — impacket, netexec, certipy-ad, bloodyAD, coercer, ldapdomaindump, adidnsdump, pywerview, enum4linux-ng, smbmap, minikerberos, donpapi *(pipx)*; kerbrute *(go)*; Responder, krbrelayx, kerberoast *(git)*; crowbar *(pipx from git)*; evil-winrm *(gem)*; bloodhound-ce-python *(dedicated venv)*.

**Web** — ffuf, gobuster, httpx, nuclei, subfinder, naabu, katana, dalfox, gowitness *(go)*; feroxbuster *(release)*; sqlmap, joomscan, whatweb *(git)*; mitmproxy, wafw00f, arjun, sublist3r, wfuzz *(pipx)*; wpscan *(gem)*; Burp Suite Community. whatweb is a checkout rather than the `whatweb` deb because the archive still ships 0.5.5 while upstream is on 0.6.x, and the tool *is* its plugin corpus — `git pull` updates the fingerprints, a `.deb` freezes them for the release cycle. Its only non-stdlib dependency, the `addressable` gem, is installed by name (module 30 also installs wpscan, which happens to pull it, but that ordering is not something to rely on).

**Delivery** — nginx + `libnginx-mod-http-headers-more-filter` *(apt, `webserver.apt`)*, serving `/var/www/html` on :80. nginx over apache2 because Apache cannot delete its `Server` header — `ServerTokens Prod` still answers `Server: Apache`, and `mod_headers` cannot unset it; nginx's `server_tokens off` only drops the version, and `more_clear_headers` removes the header outright. A client sees `Content-Type`, `Content-Length`, `Connection`, `Accept-Ranges` and nothing else; wrong path, denied method and server error are all one bodyless 404. The webroot is chowned to you, so payloads go in without sudo. Access logs are kept on purpose — they are the record of which target pulled what.

**Cloud** — awscli v2, azure-cli, gcloud, kubectl; pacu, scoutsuite, prowler, roadrecon, roadtx *(pipx)*; trufflehog *(release)*.

**RE / binary / mobile** — Ghidra, gdb + pwndbg, radare2, binwalk, edb-debugger, checksec, ltrace, strace, patchelf; pwntools, ropper, ROPgadget, frida-tools, objection, volatility3, flask-unsign, maigret *(pipx)*; apktool, jadx, dex2jar.

**Payload dev** — mingw-w64, gcc/g++-mingw-w64, wine, wine32/64, mono-complete; garble *(go)*; SharpCollection, ysoserial, DotNetToJScript, RunasCs, mimikatz, BeEF.

**Wireless / SDR / BT** — aircrack-ng, reaver, bully, cowpatty, mdk4, bluez, rfkill, iw, wireless-tools, rtl-sdr, hackrf, gqrx-sdr, hcxtools, hcxdumptool. **These need USB passthrough of a real adapter — a VM has no radios by default.**

**Repos** — PEASS-ng, PayloadsAllTheThings, InternalAllTheThings, HardwareAllTheThings, GTFOBins, PayloadsAllThePDFs, hacktricks, markdown, FindFrontableDomains, joomscan, nishang, PowerSploit, PowerUpSQL, Certify, ESC, krbrelayx, MSI-AlwaysInstallElevated, SharpCollection, SuperSharpShooter, DotNetToJScript, EvilClippy, SCShell, chisel, dnscat2, reverse_ssh.

**Binaries** — pspy32/64, PrintSpoofer32/64, GodPotato, SysinternalsSuite, putty-tools.

## First run

1. Minimal Ubuntu 26.04 install, no GNOME. Create your user, install `open-vm-tools`, add the `/mnt` share fstab line.

2. **Install the bootstrap prerequisites.** A minimal Ubuntu install has no `git`, so you cannot clone the repo that installs `git` — break the loop by hand first:

   ```bash
   sudo apt update
   sudo apt install -y git openssh-client ca-certificates curl
   ```

   `git` to clone, `openssh-client` for `ssh-keygen`, `ca-certificates` + `curl` so the vendor installers in modules 00/40/50 can reach their download endpoints. Everything else comes from `tools.d/base.apt` once `bootstrap.sh` runs.

3. Clone this repo. **No SSH key or GitHub account is needed** — every repo the modules clone, including the toolkit, resolves over https:

   ```bash
   git clone https://github.com/desterhuizen/w1ld0s.git
   ```

4. `./bootstrap.sh` — runs `00 → 05 → 10 → 20 → … → 99`. Re-runnable; fix forward on any module that warns.
5. Migrate secrets: `./bootstrap.sh 99` prints the checklist and shows what's still missing.
6. *Optional, and only if you keep private repos:* write their clone URLs into `tools.d/private.git` (one per line, gitignored) and run `./bootstrap.sh 95`. It registers this box's key with GitHub, then clones them.
7. Log out and pick your session at the greeter (GNOME or i3 — both are listed), open a new zsh, `hash -r`. If the desktop came up unbranded, run `w1ld0s-wallpaper` and `w1ld0s-gnome` from inside the session.
8. **Snapshot the VM as `clean-base`.**

## Verification

```bash
pipx list                      # one venv per tool
impacket-secretsdump -h
nxc --version
certipy -h
bloodhound-ce-python -h        # resolves from the dedicated venv
echo $ROCKYOU && ls -l "$ROCKYOU"

getent passwd "$USER" | cut -d: -f7                       # /usr/bin/zsh
diff <(bash -lic 'echo $LS_COLORS' 2>/dev/null | tail -1) \
     <(zsh  -ic  'echo $LS_COLORS' 2>/dev/null | tail -1)  # no output = colours match
zsh -ic 'echo ok' 2>&1 | grep -v '^ok$'                    # any output is a broken line in ~/.zshrc

whatweb --version                                          # exits 1 listing gems if addressable is missing
whatweb 127.0.0.1                                          # runs through the ~/.local/bin symlink

echo hi > /var/www/html/probe.txt                          # webroot is yours, no sudo
curl -sI http://127.0.0.1/probe.txt                        # Content-Type/Length/Connection/Accept-Ranges only
curl -si http://127.0.0.1/nope | head -3                   # 404, empty body, no Server
```

The shell is zsh (oh-my-zsh, its own prompt), but the **colours are bash's**: the w1ld0s block runs the same `dircolors -b` Ubuntu's stock `~/.bashrc` runs — honouring `~/.dircolors` if you drop one in — and hands the same table to zsh's completion menu, which is uncoloured otherwise. It is set outright rather than left to oh-my-zsh, which only calls `dircolors` when `LS_COLORS` is empty and so quietly diverges from bash on any box where something exports it first.

Check the aliases resolve in a fresh zsh (`htricks`, `gtfo`, `ysorerial`, `$IP`), that i3 starts with your config and fonts, and that a second full `./bootstrap.sh` run changes nothing. Then snapshot.

Branding is the one area where `module X done` proves least — verify it against box state, not the log:

```bash
grep ImageDir /usr/share/plymouth/themes/w1ld0s/w1ld0s.plymouth   # must end in /w1ld0s
sudo grep -E 'GRUB_(TIMEOUT|BACKGROUND)' /etc/default/grub
sudo strings /var/lib/gdm3/greeter-dconf-defaults | grep w1ld0s   # greeter db recompiled
gsettings get org.gnome.shell favorite-apps
gsettings get org.gnome.shell.extensions.dash-to-dock dock-fixed  # false = actually autohides
gsettings get org.gnome.Ptyxis font-name                          # 'Fira Code Medium 10'
```

The Ptyxis palette is the one setting whose value proves nothing on its own — the key stores a palette *name*, so it reads back `'w1ld0s'` whether or not the keyfile parsed. Check the file itself:

```bash
python3 -c "from gi.repository import GLib; k=GLib.KeyFile(); \
k.load_from_file('$HOME/.local/share/org.gnome.Ptyxis/palettes/w1ld0s.palette', 0); \
print(k.get_string('Palette','Name'), len(k.get_keys('Palette')[0]), 'keys')"   # w1ld0s 20 keys
```

App-grid and folder changes need a shell restart; on Wayland that means logging out and back in, since `Alt+F2 r` is X11-only. Ptyxis reads palette files at startup, so close every window before judging its colours.

## Pinning

The first build runs unpinned to get a working VM fast. Once it's green and snapshotted, the versions that worked are frozen back into the manifests — **the manifests are the lockfile**, and `.gitignore` force-tracks them with `!tools.d/*`. A local-only pin would defeat the purpose, which is that the *next* VM rebuilds identically.

As of the aarch64 build of 2026-08-15 everything below is pinned:

- `pipx list` → `name  name==version` in `tools.d/*.pipx`. Use the **two-field** form: `pipx_tool` checks for an existing install by the bare package name, so a lone `impacket==0.13.1` would try to reinstall on every run.
- Tools with no PyPI release pin a git ref instead — `netexec` to a commit, `enum4linux-ng` to a tag.
- `go version -m ~/go/bin/<tool>` → `module@vX.Y.Z` in `tools.d/*.go`. Keep the *install* path and append the *module* version (`…/httpx/cmd/httpx@v1.10.0`).
- `tools.d/releases.gh` and the `gh_release` calls in modules 30/40/50/60 pin with `owner/repo@tag`. Pin the **tag**, never the resolved asset filename — the filename carries the arch, so a pinned filename cannot be rebuilt on the other architecture. A tag that doesn't exist 404s and warns; it never falls back to latest.
- Gems pin with `-v` (`evil-winrm 3.9`, `wpscan 4.1.0`, `addressable 2.9.0`); `GO_VERSION` in `modules/00-base.sh`.
- Git checkouts (sqlmap, joomscan, whatweb, Responder, …) are the exception: `clone_or_pull` tracks the default branch and fast-forwards on every run. That is deliberate for tools whose value is a signature/plugin corpus, but it does mean those are the parts of the box a re-run can change.

To unpin a single tool, replace its version with `@latest` / drop the `==`, re-run that module, and freeze the new version back.

## Known gaps

- `assets/zshrc` is imported but no module installs it — `modules/00-base.sh` appends its own block to whatever `~/.zshrc` oh-my-zsh creates, and that block already sources the toolkit aliases. The asset now duplicates the block rather than contradicting it, but it is still dead: either wire it up with `install_asset zshrc "$HOME/.zshrc"` (before the block is appended) or drop it.
- `assets/i3/i3-workspace-1.json` is an i3 layout dump that nothing restores. Wire it into the i3 config with `append_layout` if you want it.
- Burp's unattended install depends on PortSwigger's download endpoint not requiring a browser; it warns and points at a manual installer if that fails. The installer is arch-selected (`type=Linux` is x86_64-only, `type=LinuxArm64` for aarch64).
- Veil is dropped: its setup needs wine32 + mono, which module 60 already skips as x86_64-only, and it has been unmaintained since 2021. The recipe is kept in `tools.d/kali-longtail.src` for x86_64 boxes.
- The greeter background uses Ubuntu's `com.ubuntu.login-screen` schema. On a non-Ubuntu GNOME that schema is absent and the greeter keeps its stock background — only the dark styling and banner apply.
- The greeter sets **no** `org.gnome.login-screen logo`: the background already carries the logo, and GNOME 50 draws that key unscaled — `loginDialog._updateLogoTexture` passes `load_file_async(file, -1, -1, …)` (older shells capped it at 48px) and anchors the image at `(dialog_height - image_height) * 0.96` to match the Plymouth watermark. Ubuntu's watermark is 187x72 and lands at the bottom edge; the 480x480 `w1ld0s-splash.png` covered the password entry. Restoring a logo means shipping a separate ~72px-tall asset, not reusing the splash.
- nginx is **enabled at boot**, so a fresh boot listens on :80 with an empty webroot (answering a bodyless 404). That is the useful default for payload delivery; turn it off with `sudo systemctl disable --now nginx` if you would rather start it per engagement. The headers-more filter depends on a versioned `nginx-abi-<x.y.z>`, so an nginx ABI bump can leave it briefly uninstallable — module 35 detects that and drops the `more_*` lines rather than letting an unknown directive stop nginx from starting, at the cost of sending `Server: nginx` until the module catches up.
- Module 07 restyles GDM through the supported dconf drop-in only. The greeter's *widget* theme (panel colours, entry fields) comes from `gdm-theme.gresource`, which `update-alternatives` resolves to Yaru at priority 15 — note that overwriting `/usr/share/gnome-shell/gnome-shell-theme.gresource`, the fix most guides give, is silently shadowed by that and does nothing.
- The two terminals are styled twice from one set of colours: `assets/terminator/config` holds them as a palette string, `assets/ptyxis/w1ld0s.palette` as a keyfile. Change one and the other drifts — there is no shared source.
- `tools.d/gnome.folder` lists a few tools nothing installs yet (wireshark, zaproxy are deliberately absent). Entries with no `.desktop` file are filtered out at apply time, so the list is safe to share across builds.
- Whether to clone the large legacy `/mnt/hacking/tools/` kit or leave it on the mount is still undecided.

## License

AGPLv3 — see [LICENSE](../LICENSE). Read [NOTICE](../NOTICE) before use: this provisions
an offensive-security workstation, and using that tooling against systems you are not
authorized to test is a criminal offense in most jurisdictions.

The companion toolkit, [w1ld0s-tools](https://github.com/desterhuizen/w1ld0s-tools), is
under the same license.
