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
docs/                 this file, the AD collection cheatsheet, the Debian port note
tests/                check.sh (static, per push), verify-box.sh (on a real box),
                      box-state.sh (idempotence digest), freeze-pins.sh (installed
                      versions in manifest shape), scan-lab.sh (real scans against
                      the lab), lab/ (its fixtures), Dockerfile + check-docker.sh
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

Both stacks are installed and they coexist. **i3 is a session, not a display manager choice** — the greeter lists `i3` next to the GNOME session and module 05 makes it the default, while module 07 tidies the GNOME shell either way.

**The display manager is lightdm and the default session is i3.** These are two settings, not one, and the second is the one that matters: the session type is decided by which `.desktop` the greeter launches, not by who launches it. Brave and Burp Suite misbehave under Wayland, and on Ubuntu 26.04 there is no X11 GNOME to fall back to — GNOME Shell 50 dropped X11 support, `ubuntu-session` ships only `/usr/share/wayland-sessions/ubuntu.desktop`, and neither `gnome-session-xsession` nor `ubuntu-desktop-xorg` exists in the archive. i3 is therefore the only X11 desktop on the box, so module 05 writes `user-session=i3` into `/etc/lightdm/lightdm.conf.d/90-w1ld0s-session.conf`. That sets the default, not a restriction: the GNOME Wayland session stays in the picker.

Module 05 switches the display manager through debconf (`dpkg-reconfigure lightdm`) rather than `systemctl enable` — Ubuntu Desktop owns `/etc/systemd/system/display-manager.service`, so a plain unit toggle fails with "file already exists". It then **asserts the result instead of trusting it**, because under `DEBIAN_FRONTEND=noninteractive` that reconfigure has been observed to leave `/etc/X11/default-display-manager` untouched on a real build. If the file or the `display-manager.service` symlink still disagree afterwards, the module writes them directly and warns.

gdm3 stays **installed but inactive**; purging it takes `ubuntu-desktop` with it. To go back:

```bash
sudo dpkg-reconfigure gdm3 && ./bootstrap.sh 06     # 06 re-brands the GDM greeter
```

Session settings need a live D-Bus session bus, which `bootstrap.sh` usually does not have when run from a tty. Modules 05 and 07 therefore generate `w1ld0s-wallpaper` and `w1ld0s-gnome` in `~/.local/bin` and try them once — re-run either from inside your desktop session if it reported nothing applied.

## Modules

| Module | What it does |
| --- | --- |
| `00-base` | `base.apt`, Go 1.24.5 to `/usr/local/go`, rustup, pipx, oh-my-zsh, **zsh as the login shell** (`sudo chsh`, `usermod` fallback, result checked against `/etc/passwd`), tmux.conf + TPM, the `~/.zshrc` w1ld0s block (PATH, `$EDITOR`, `$ROCKYOU`, bash-identical colours, aliases sourcing), gunzips rockyou in place |
| `05-desktop-i3` | `desktop.apt`, Brave + VS Code vendor repos, imports i3 config/i3blocks/fonts/terminator, i3blocks-contrib, the `i3-workspace-1.json` layout `setup_workspace` restores. Makes **lightdm** the display manager via debconf and **i3 the default session**, then asserts both landed (see above) |
| `06-boot-branding` | GRUB menu background, the Plymouth boot splash and the **login greeter**, all using the w1ld0s logo. Clones Ubuntu's stock `spinner` theme and swaps only the watermark, so the tested LUKS passphrase prompt is preserved. Rewrites `/etc/default/grub` (including `GRUB_TIMEOUT_STYLE=menu`, without which the background never draws) and the initramfs; brands whichever DM is active (normally lightdm, via its greeter conf; gdm3 via `/usr/share/gdm/dconf/95-w1ld0s` if you switched back) |
| `07-gnome-shell` | GNOME session cleanup from `tools.d/gnome.*`: minimal dock favourites, dock to the bottom and autohiding, CLI/duplicate entries hidden from the app grid, GUI pentest tools grouped into a `w1ld0s` folder, desktop icons and the snap/web search providers disabled. Also styles **Ptyxis** (GNOME's terminal) to match terminator — same gruvbox palette, Fira Code, 0.9 opacity. Generates `w1ld0s-gnome`; no-ops on a box with no GNOME |
| `10-python-isolation` | Ensures pipx and the shared venv dir; prints and records the isolation policy |
| `20-ad-network` | `ad.pipx`, kerbrute, Responder, krbrelayx, kerberoast, crowbar, evil-winrm, **BloodHound-CE ingestor in a dedicated venv with sign-capable ldap3** |
| `30-web` | `web.go` + nuclei templates, feroxbuster, sqlmap, joomscan, whatweb (+ its `addressable` gem), `web.pipx`, wpscan, Burp Suite Community (unattended installer, plus a system-wide `/usr/local/bin/burpsuite` symlink alongside the user `burp` shim) |
| `35-webserver` | nginx as a **quiet static file host** for `/var/www/html`: no `Server`/`Date`/`Last-Modified`/`ETag`, no default page, no directory listing, every non-file a bodyless 404. Config from `assets/nginx/w1ld0s.conf`; validates with `nginx -t` before touching the service and unhooks itself if that fails |
| `40-cloud` | AWS CLI v2, Azure CLI, gcloud, kubectl, `cloud.pipx`, trufflehog |
| `50-re-binary` | gdb/radare2/binwalk/checksec/ltrace/strace/patchelf, pwndbg (+uv), `re.pipx`, Ghidra, apktool/jadx/dex2jar |
| `60-payload-dev` | mingw-w64 cross-compile + wine + mono, garble, SharpCollection, ysoserial jar, DotNetToJScript, RunasCs, mimikatz, BeEF, **Metasploit Framework** from Rapid7's nightly apt repo (added by hand — key, `signed-by` sources line, `apt-get install` — rather than piping `msfinstall` into a root shell) |
| `70-wireless` | aircrack-ng/reaver/bully/cowpatty/mdk4, bluez, rtl-sdr/hackrf/gqrx, hcxtools + hcxdumptool from source |
| `80-repos-binaries` | Clones `repos.git`, builds **ligolo-ng** (`make all` — proxy + agent, linux/windows, both arches) and links `ligolo-proxy` into `~/.local/bin` *and* `/usr/local/bin`, links **searchsploit** out of the exploitdb clone and writes a `~/.searchsploit_rc` naming it, fetches the binary rows of `releases.gh`, Sysinternals Suite, putty-tools |
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

**Payload dev** — mingw-w64, gcc/g++-mingw-w64, wine, wine32/64, mono-complete; garble *(go)*; SharpCollection, ysoserial, DotNetToJScript, RunasCs, mimikatz, BeEF; metasploit-framework *(Rapid7 nightly apt repo)*.

**Pivoting / exploit search** — ligolo-ng *(built from source, `ligolo-proxy` on both the user and the system PATH)*; reverse_ssh, chisel, dnscat2 *(git)*; exploitdb + `searchsploit` *(git, GitLab)*.

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

## Updating a box

There is no update command, and that is the design: the box you rebuild from a
bumped manifest is reproducible, the box you mutate in place is not. What
follows is what actually moves, so nobody has to guess.

**Rebuild from bumped manifests — the supported path.** Every `.pipx` and
`.gh` pin, the gems, `GO_VERSION`, and every tool behind a module presence
guard (Ghidra, jadx, apktool, Burp, feroxbuster, trufflehog, `aws`, `kubectl`,
hcxtools) takes effect on a **fresh VM only**. On a live box the guards are all
true, so a bumped pin is a no-op — `pipx_tool` compares the bare package name
and `gh_release` returns on `[ -e "$dest" ]` before the tag is read. Bump the
manifest, build a new VM, verify, snapshot, discard the old one.

**Moves on its own, on every run.** Every `clone_or_pull` checkout — sqlmap,
whatweb, joomscan, Responder, dex2jar, the toolkit — tracks its default branch
and fast-forwards. That is deliberate for tools whose value is a signature or
plugin corpus. `go install` re-runs unconditionally and so converges to the
`.go` pin. `apt_install` resolves to the archive candidate, which is also how
the apt-repo-backed `az` and `gcloud` stay current. `nuclei -update-templates`
runs every time module 30 does.

**Not done at all: OS package upgrades.** `bootstrap.sh` never runs `apt-get
upgrade`, deliberately — a pentest box that changes underneath an engagement is
a hazard, not a convenience. Patch it yourself between engagements:

```bash
sudo apt-get update && sudo apt-get upgrade
```

Never `dist-upgrade` or `full-upgrade`: both are permitted to **remove**
packages to satisfy a new dependency set, which is exactly what `--no-remove`
exists to prevent (see the `gcc-multilib:i386` note at `lib/common.sh:116-121`).
`unattended-upgrades` stays off for the same reason — `verify-box.sh` warns if
it finds it enabled and prints the command to disable it.

**Bumping the pins.** Freezing a green build back into the lockfile is
mechanical rather than fifty hand-transcriptions:

```bash
./tests/verify-box.sh -v            # what has drifted from the manifests
./tests/freeze-pins.sh --diff       # exactly which pins the box disagrees with
./tests/freeze-pins.sh ad.pipx      # review, then paste into tools.d/ad.pipx
git diff tools.d/                   # the lockfile change, reviewable
./tests/check-docker.sh --strict    # grammar and pinning rules still hold
```

`freeze-pins.sh` is a line-preserving transform, not a generator: comments,
ordering and column alignment survive, so only the version tokens move. It
prints and never writes — do **not** redirect it over its own input, which
truncates the file before it is read.

## Checks

Four tiers, deliberately unequal in what they can prove.

| Tier | What | When |
|---|---|---|
| Static | `tests/check.sh` — manifest shape and pinning, https-only clone URLs, `ALL_MODULES` vs the filesystem vs this file, the transitive-`die` trap, `.gitignore` integrity, secret patterns, shellcheck | Every push; seconds |
| Container | `.github/workflows/smoke.yml` — runs `./bootstrap.sh` twice in `ubuntu:26.04` and asserts the second run changes nothing; also `nginx -t` and `i3 -C` against the shipped configs | Every PR into `main`; weekly; on demand |
| Box | `tests/verify-box.sh` — presence, box state, **drift between the manifest pins and the installed versions**, and that every pipx tool still imports; see [Verification](#verification) | By hand, after a real install |
| Scan | `tests/scan-lab.sh` — real scans against two throwaway Docker targets, asserting that nmap, httpx, ffuf, whatweb, nuclei, ldapsearch, smbclient, netexec, smbmap and enum4linux-ng each still report the facts they should; see [Scan lab](#scan-lab) | By hand, after upgrading a tool; needs Docker on your workstation; ~5 min |

```bash
./tests/check.sh              # from a Linux box or the CI runner
./tests/check-docker.sh       # from anywhere Docker runs, including macOS
./tests/check.sh --strict     # warnings become failures
./tests/freeze-pins.sh --diff # on a box: which pins no longer match it
./tests/scan-lab.sh -v        # on a box, with the lab up on your workstation
```

`check.sh` targets Linux, bash 5 and GNU userland on purpose — it is not macOS
compatible. `check-docker.sh` runs the identical script in the same `ubuntu:26.04`
image CI uses, so "it passed locally" and "it passed in CI" mean the same thing.

**What none of this catches.** Anything you have to look at: GRUB, Plymouth, the LUKS
prompt, the greeter, the dock, wallpapers, fonts. Anything needing systemd or hardware
— nginx surviving a reboot, `vmtoolsd`, wireless, SDR, Bluetooth, the VMware share.
Whether a tool *works* rather than merely *installs* — partly closed now, and worth
being precise about what by. `verify-box.sh` runs every pipx tool and fails if it
tracebacks, which is the failure that killed donpapi, wfuzz and ropper: all three
installed cleanly and died on first import. `scan-lab.sh` goes further and proves
`netexec` really authenticates and enumerates shares against a live domain controller
over both SMB and LDAP. Neither touches Kerberos against a *Windows* DC, ADCS, signing
enforcement, LAPS or gMSA — the lab is Samba, and Samba is not Windows. And neither can
tell you whether a pinned version is the *right* version. A green badge means the repo is consistent and a
container provisioned — never that the box boots branded and working.

## Verification

Run the verifier on the box, after `./bootstrap.sh` and a reboot:

```bash
./tests/verify-box.sh          # auto-detects which modules ran
./tests/verify-box.sh 00 35    # only these groups
./tests/verify-box.sh -v       # also print every passing check
```

It asserts everything that can be asserted from a shell — every `.pipx`, `.go` and
`releases.gh` tool actually present **and every pipx tool actually able to run**,
zsh as the login shell, exactly one `~/.zshrc`
w1ld0s block, bash-identical `LS_COLORS`, a clean `zsh -ic` startup, the webserver's
header suppression and bodyless 404, Plymouth's `ImageDir`, the GRUB keys, the
recompiled greeter database, and the Ptyxis palette keyfile — and then prints the
short list of things that still need a human eye.

The run check is worth explaining, because it is cheap and catches the thing that
has actually bitten this repo. Every pipx package is run once — `pipx list --json`
says which console script each one installed, so nothing has to guess that
`netexec` ships `nxc` or that impacket ships seventy scripts under their own names
— and the assertion is that the output carries no `Traceback`, `ModuleNotFoundError`
or `ImportError`. Not that it exits 0: argparse-style CLIs disagree about what
`--help` should exit with, while a venv broken by an interpreter bump is
unambiguous. That is exactly how donpapi, wfuzz and ropper died — all three
installed cleanly and failed on first import. Go binaries are deliberately not
covered: a binary that execs at all has no import step to fail.

It also compares the **installed version** of every `.pipx` and `.go` entry against
the pin in the manifest, which presence alone never caught: a box running impacket
0.12 against a manifest pinning 0.13.1 used to report fully green. A mismatch is a
`warn`, not a `fail` — the tool works; what has stopped being true is that the
manifests are the lockfile, so the next VM built from this commit will not be this
box. `--strict` promotes it if you want a hard gate. **Expect a real box to go amber
here as upstream moves**; that is the check doing its job, not something to fix by
demoting the warnings. Resolve it in whichever direction is right: bump the pin and
rebuild, or run `./tests/freeze-pins.sh` to move the manifest onto what the box has
proved. A `git+` pin is compared against the spec pipx recorded at install time
(`pipx_metadata.json`), since `pipx list` reports a package version rather than a ref.

Run it **inside a desktop session** if you want the GNOME group checked: `gsettings`
returns empty over SSH, so the script skips that group with a note rather than
manufacturing failures. Groups whose module never ran are skipped too, so running a
subset of the bootstrap does not produce a wall of red.

The shell is zsh (oh-my-zsh, its own prompt), but the **colours are bash's**: the w1ld0s block runs the same `dircolors -b` Ubuntu's stock `~/.bashrc` runs — honouring `~/.dircolors` if you drop one in — and hands the same table to zsh's completion menu, which is uncoloured otherwise. It is set outright rather than left to oh-my-zsh, which only calls `dircolors` when `LS_COLORS` is empty and so quietly diverges from bash on any box where something exports it first.

Branding is the one area where `module X done` proves least — verify it against box state, not the log: That is why the verifier reads Plymouth's `.plymouth` file, greps
`/etc/default/grub`, and `strings` the compiled greeter database instead of trusting
the log.

The Ptyxis palette is the one setting whose value proves nothing on its own — the key stores a palette *name*, so it reads back `'w1ld0s'` whether or not the keyfile parsed. Check the file itself: The verifier parses it and counts the keys, which is the only real
evidence the palette landed.

App-grid and folder changes need a shell restart; on Wayland that means logging out and back in, since `Alt+F2 r` is X11-only. Ptyxis reads palette files at startup, so close every window before judging its colours.

To confirm the idempotence invariant explicitly:

```bash
./tests/box-state.sh > /tmp/s1 && ./bootstrap.sh && ./tests/box-state.sh > /tmp/s2
diff /tmp/s1 /tmp/s2      # any output at all is an idempotence defect
```

`box-state.sh` prints only what must be byte-stable — the `~/.zshrc` digest and its
marker counts, the login shell, the `~/.local/bin` symlink set with targets, and any
`*.w1ld0s.bak` files. It deliberately does not diff filesystem trees: `clone_or_pull`
fast-forwards every checkout on every run by design, so a tree diff would always be
noisy and would prove nothing.

## Scan lab

`tests/verify-box.sh` can tell you a tool is installed and imports. It cannot tell
you the tool still returns the right answer. `tests/scan-lab.sh` closes that: it
points ten tools at two throwaway Docker containers whose answers are known in
advance, and asserts a handful of specific facts from each.

The lab runs on **your workstation, not the box** — the box is normally a guest
VM, and nesting Docker inside it would make Docker a provisioning prerequisite
for no benefit. The stack publishes ports on the host and the guest scans back to
the host's address on the hypervisor network. Full setup, including how to find
that address for each hypervisor, is in [`tests/lab/README.md`](../tests/lab/README.md).

```sh
docker compose -f tests/lab/compose.yml up -d   # on the workstation
```
```bash
echo 192.168.x.1 > tests/lab/target             # on the box, once per VM
./tests/scan-lab.sh -v
./tests/scan-lab.sh nxc ffuf                    # just these, while iterating
```

| Target | Image | Asserted by |
|---|---|---|
| DVWA (Apache/PHP/MariaDB) | `ghcr.io/digininja/dvwa` | nmap, httpx, ffuf, whatweb, nuclei |
| Samba 4.24.6 as an AD DC | `diegogslomp/samba-ad-dc` | nmap, ldapsearch, smbclient, netexec, smbmap, ldapdomaindump, kerbrute, impacket, enum4linux-ng |

Both images are pinned by **digest**, not tag: neither upstream publishes a stable
semantic version, and a fixture whose surface moves cannot answer "did my upgrade
break this". The digest is the lockfile, the same discipline `tools.d/` uses.

The rule every assertion follows is **anchor on tokens the fixture supplies, never
on tokens the tool supplies** — `DC1`, `login.php`, `lab.w1ld0s.local`, never a
version string or a column position. Two consequences worth knowing:

- **nuclei is asserted structurally** — that its corpus loaded and it exited
  cleanly, not that any particular template fired. The corpus updates
  independently of the pinned binary, so any finding-level assertion would rot
  within weeks. What actually breaks on a nuclei upgrade is the corpus failing to
  parse, and that is what the assertion catches. It skips entirely if no corpus
  is on disk, because `-duc` makes nuclei hard-fail without one.
- **Negative assertions carry real weight.** ffuf must *not* report the two paths
  that do not exist, kerbrute must report exactly 1 of 3 usernames valid, and nmap
  must not call port 64999 open. A scanner that reports everything passes every
  positive test ever written.

The preflight is deliberately fussy about the difference between *something is
listening* and *the fixture is listening*, because the target is now your own
workstation. No target configured, or nothing on the port, is a `skip` and exit 0 —
an absent lab is not a broken tool. Something answering on :80 that is not DVWA is
a single `FAIL` naming that fact, rather than five tool failures that blame the
tools.

### Before and after an upgrade

```bash
./tests/scan-lab.sh -v | tee ~/before.txt
$EDITOR tools.d/web.go && ./bootstrap.sh 30
./tests/scan-lab.sh -v | tee ~/after.txt
diff -u <(grep -v '^\[note\]' ~/before.txt) <(grep -v '^\[note\]' ~/after.txt)
```

Two runs against an unchanged box differ by exactly one line — the `[note]` giving
the timestamped transcript directory — which is why the diff drops the note lines.
Everything else, including the nuclei finding count, is stable.

A regression prints the tool, the fact and the transcript path, and exits non-zero,
so the second run answers the question on its own. `diff -ru` between the two
transcript directories under `~/.local/tmp/w1ld0s-scan-lab/` answers the follow-up
question of *what* changed.

One caveat that decides how you run this: **a bumped `.pipx` or `.gh` pin is a
no-op on an already-provisioned box.** `pipx_tool` matches by bare name and
`gh_release` returns on `[ -e "$dest" ]` before the tag is read, so re-running the
module changes nothing and the two scans will agree. `.go` pins *do* re-fetch.
For pipx and release pins the honest before/after needs a fresh VM — which is why
this belongs next to `verify-box.sh` in the first-run procedure rather than as a
separate ritual you have to remember.

## Pinning

The first build runs unpinned to get a working VM fast. Once it's green and snapshotted, the versions that worked are frozen back into the manifests — **the manifests are the lockfile**, and `.gitignore` force-tracks them with `!tools.d/*`. A local-only pin would defeat the purpose, which is that the *next* VM rebuilds identically.

As of the aarch64 build of 2026-08-15 everything below is pinned:

- `pipx list` → `name  name==version` in `tools.d/*.pipx`. Use the **two-field** form: `pipx_tool` checks for an existing install by the bare package name, so a lone `impacket==0.13.1` would try to reinstall on every run.
- Tools with no PyPI release pin a git ref instead — `netexec` to a commit, `enum4linux-ng` to a tag.
- `go version -m ~/go/bin/<tool>` → `module@vX.Y.Z` in `tools.d/*.go`. Keep the *install* path and append the *module* version (`…/httpx/cmd/httpx@v1.10.0`).
- `tools.d/releases.gh` and the `gh_release` calls in modules 30/40/50/60 pin with `owner/repo@tag`. Pin the **tag**, never the resolved asset filename — the filename carries the arch, so a pinned filename cannot be rebuilt on the other architecture. A tag that doesn't exist 404s and warns; it never falls back to latest.
- Gems pin with `-v` (`evil-winrm 3.9`, `wpscan 4.1.0`, `addressable 2.9.0`); `GO_VERSION` in `modules/00-base.sh`.
- Metasploit is the one apt source that is **not** pinnable: Rapid7 publishes a rolling nightly under the single `lucid` suite, so a rebuild gets whatever nightly is current that day. There is no tag to freeze.
- Git checkouts (sqlmap, joomscan, whatweb, Responder, ligolo-ng, exploitdb, …) are the exception: `clone_or_pull` tracks the default branch and fast-forwards on every run. That is deliberate for tools whose value is a signature/plugin corpus, but it does mean those are the parts of the box a re-run can change.

**A bumped pin lands on the next VM, not on the box you are sitting at.** Only the
`.go` manifests behave otherwise, because `go_install_list` has no presence check and
re-runs `go install` every time. For `.pipx`, `gh_release` and every tool behind a
module guard, editing the manifest and re-running the module changes nothing — see
[Updating a box](#updating-a-box).

So the loop is: build, verify, freeze, rebuild.

```bash
./tests/freeze-pins.sh --diff       # which pins this box disagrees with
./tests/freeze-pins.sh ad.pipx      # review, then paste into tools.d/ad.pipx
git diff tools.d/                   # commit the lockfile change with the build that proved it
```

To move a single tool forward deliberately, bump its pin, provision a fresh VM, and
freeze back whatever came out green.

## Known gaps

- **`releases.gh` tags are not drift-checked.** `gh_release` writes the asset and keeps no record of which tag produced it, so nothing on the box can answer "is this feroxbuster the pinned one?" Fixing it means a provenance sidecar written next to each `$dest` after a successful download; until then `freeze-pins.sh` skips `.gh` and `verify-box.sh` checks those rows for presence only.
- **Pins that live in module source are not drift-checked either** — the gems (`evil-winrm 3.9`, `wpscan 4.1.0`, `addressable 2.9.0`), `GO_VERSION`, and the inline `gh_release` tags in modules 30/40/50/60. Only pins in `tools.d/*` are compared, because that is where a manifest can be read without grepping shell source.
- **feroxbuster, trufflehog and RunasCs are pinned in two places** — `tools.d/releases.gh` and inline in modules 30/40/60 — so bumping either one alone leaves the two disagreeing.
- Git-cloned tools (sqlmap, whatweb, Responder, dex2jar, …) drift on every run by design and cannot be drift-checked: `clone_or_pull` tracks a branch, and there is no ref to compare against.
- `have evil-winrm` in `modules/20-ad-network.sh` is false during bootstrap — the gem bin dir is only appended to `~/.zshrc`, never exported into the running shell — so that `gem install` re-runs on every bootstrap. It exits 0 reporting the gem is already installed, so it costs seconds rather than correctness. Same shape for `wpscan` in module 30.
- `assets/zshrc` is imported but no module installs it — `modules/00-base.sh` appends its own block to whatever `~/.zshrc` oh-my-zsh creates, and that block already sources the toolkit aliases. The asset now duplicates the block rather than contradicting it, but it is still dead: either wire it up with `install_asset zshrc "$HOME/.zshrc"` (before the block is appended) or drop it.
- Burp's unattended install depends on PortSwigger's download endpoint not requiring a browser; it warns and points at a manual installer if that fails. The installer is arch-selected (`type=Linux` is x86_64-only, `type=LinuxArm64` for aarch64).
- Burp gets two names: `~/.local/bin/burp` (the usual `shim`, this user's PATH only) and `/usr/local/bin/burpsuite` (system-wide, so root and cron can reach it). The install itself stays under `/opt/w1ld0s`, which is where module 07 looks when it generates the GNOME launcher. The `/usr/local/bin` link is created *outside* module 30's `[ ! -d ]` install guard on purpose — inside it, the link would only ever appear on a freshly built VM, never on a box that already had Burp.
- Veil is dropped: its setup needs wine32 + mono, which module 60 already skips as x86_64-only, and it has been unmaintained since 2021. The recipe is kept in `tools.d/kali-longtail.src` for x86_64 boxes.
- The lightdm greeter is a plain INI at `/etc/lightdm/lightdm-gtk-greeter.conf`, rewritten wholesale by module 06 — a hand-edited one is backed up to `.w1ld0s.bak` once, the same way `install_asset` does. It carries no banner: `banner-message-text` is a GDM key with no lightdm-gtk-greeter equivalent.
- The next two bullets describe module 06's **gdm3 fallback branch**, which only runs if you switch back to gdm3. The traps are still live, so they are kept.
- The greeter background uses Ubuntu's `com.ubuntu.login-screen` schema. On a non-Ubuntu GNOME that schema is absent and the greeter keeps its stock background — only the dark styling and banner apply.
- The greeter sets **no** `org.gnome.login-screen logo`: the background already carries the logo, and GNOME 50 draws that key unscaled — `loginDialog._updateLogoTexture` passes `load_file_async(file, -1, -1, …)` (older shells capped it at 48px) and anchors the image at `(dialog_height - image_height) * 0.96` to match the Plymouth watermark. Ubuntu's watermark is 187x72 and lands at the bottom edge; the 480x480 `w1ld0s-splash.png` covered the password entry. Restoring a logo means shipping a separate ~72px-tall asset, not reusing the splash.
- nginx is **enabled at boot**, so a fresh boot listens on :80 with an empty webroot (answering a bodyless 404). That is the useful default for payload delivery; turn it off with `sudo systemctl disable --now nginx` if you would rather start it per engagement. The headers-more filter depends on a versioned `nginx-abi-<x.y.z>`, so an nginx ABI bump can leave it briefly uninstallable — module 35 detects that and drops the `more_*` lines rather than letting an unknown directive stop nginx from starting, at the cost of sending `Server: nginx` until the module catches up.
- Module 07 restyles GDM through the supported dconf drop-in only. The greeter's *widget* theme (panel colours, entry fields) comes from `gdm-theme.gresource`, which `update-alternatives` resolves to Yaru at priority 15 — note that overwriting `/usr/share/gnome-shell/gnome-shell-theme.gresource`, the fix most guides give, is silently shadowed by that and does nothing.
- The two terminals are styled twice from one set of colours: `assets/terminator/config` holds them as a palette string, `assets/ptyxis/w1ld0s.palette` as a keyfile. Change one and the other drifts — there is no shared source.
- `tools.d/gnome.folder` lists a few tools nothing installs yet (wireshark, zaproxy are deliberately absent). Entries with no `.desktop` file are filtered out at apply time, so the list is safe to share across builds.
- **The scan lab needs Docker, which no module installs.** That is deliberate — it runs on your workstation, not the box — but it does mean `scan-lab.sh` is the one tier that cannot run unattended anywhere. It skips cleanly and exits 0 when `tests/lab/target` is absent.
- **The lab is Samba, and Samba is not Windows.** There is no ADCS role, so `certipy` cannot be exercised at all; there is no LAPS, no gMSA, and none of the Windows-specific quirks that AD tooling actually trips over. [GOAD](https://github.com/Orange-Cyberdefense/GOAD) is the real answer for that depth, but it is Vagrant plus real Windows VMs — 20GB of RAM for GOAD-Light and around 115GB of disk — so nothing here is built for it. If you do stand it up, put its DC's address in `tests/lab/target` and the AD half of `scan-lab.sh` will run against it unchanged.
- **NetBIOS name service (137/udp) is not published by the lab**, because macOS runs `netbiosd` on that port and the bind fails outright. `enum4linux-ng` loses its "NetBIOS Names and Workgroup" section as a result; its SMB-session and RPC sections still answer, and those are what the assertions use.
- **`masscan` is excluded from the scan lab** because it needs raw sockets, and a `sudo` prompt in the middle of an otherwise unattended run is worse than the coverage is worth.
- **`ligolo-ng` and `exploitdb` are built and read out of a tracked branch**, so neither has a version the manifests can hold. The ligolo build is also guarded on `dist/ligolo-ng-proxy-linux_<arch>` existing, so a `git pull` that brings in new commits does **not** rebuild — delete `dist/` (or `make clean`) when you want the pulled code. exploitdb needs no build step, so its `git pull` is the update.
- **The exploitdb checkout is the largest thing module 80 clones** — the whole Exploit-DB corpus, which is exactly what makes `searchsploit` answer from a network with no egress. The first clone dominates module 80's runtime, and there is no smaller mirror worth having (the `offensive-security/exploitdb` GitHub mirror people still link to is archived; GitLab is where it is actually published).
- **Metasploit tracks Rapid7's nightly channel, so no two VMs built on different days carry the same msf.** That is the only distribution Rapid7 offers outside the commercial installer. It also arrives with no database: `msfconsole` runs fine, but `db_nmap`, workspaces and the `hosts`/`services` tables need `sudo apt-get install postgresql && msfdb init`, which module 60 deliberately leaves to the operator because it is per-engagement state.
- Whether to clone the large legacy `/mnt/hacking/tools/` kit or leave it on the mount is still undecided.

## License

AGPLv3 — see [LICENSE](../LICENSE). Read [NOTICE](../NOTICE) before use: this provisions
an offensive-security workstation, and using that tooling against systems you are not
authorized to test is a criminal offense in most jurisdictions.

The companion toolkit, [w1ld0s-tools](https://github.com/desterhuizen/w1ld0s-tools), is
under the same license.
