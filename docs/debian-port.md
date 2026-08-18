# Porting w1ld0s to Debian

**Status: written up, not implemented.** This records what a survey of the repo found,
so the work is a small decision later rather than a re-investigation. Nothing here has
been executed or tested on a Debian box.

## Why it is nearly free

The repo turns out to be well-prepared for Debian, mostly by accident of other design
choices:

- **No release codename anywhere.** There is no `lsb_release`, no `$VERSION_CODENAME`,
  and no `noble`/`plucky`/`resolute` string in `bootstrap.sh`, `lib/`, or `modules/`.
  "Ubuntu 26.04" appears only in comments.
- **The vendor apt repos are codename-free.** Brave and VS Code
  (`modules/05-desktop-i3.sh:14,22`) pin `stable main`, and Google Cloud
  (`modules/40-cloud.sh:29`) pins `cloud-sdk main`. All three resolve on Debian
  verbatim — not one repo line needs to change.
- **Zero `.deb` downloads and zero `dpkg -i`.** Every out-of-archive binary arrives
  through `gh_release`, a vendor installer script, or a tarball. That single choice
  removes most of what usually makes a port expensive.
- **Two Debian-isms are already handled.** `modules/00-base.sh:14-15` shims
  `fdfind`→`fd` and `batcat`→`bat` only when the Debian-style names are what is
  present, so both naming schemes work. `modules/06-boot-branding.sh` already matches
  `gdm3|gdm`.
- `lib/common.sh:107` already has a `debian)` branch. It warns; it does not dispatch.

The manifests carry the rest: `releases.gh`, all four `.pipx`, both `.go` and
`repos.git` are 78 entries with no distro coupling at all.

## The delta

| Item | Location | What to do |
|---|---|---|
| Distro dispatch | `lib/common.sh:102-111` | The `case "${ID:-}"` sources `/etc/os-release` and throws the result away. Export a `W1LD0S_DISTRO`, and consult `ID_LIKE` so Mint/Pop!\_OS/Kali stop landing in the "Untested distro" arm despite being apt-compatible. |
| `gh` | `tools.d/base.apt:11` | Not in Debian stable main. Needs the `cli.github.com` apt repo, the way Brave and VS Code are already handled in module 05. |
| `ensure_python` | `lib/common.sh:154-165` | `add-apt-repository -y ppa:deadsnakes/ppa` is Ubuntu-only — PPAs do not exist on Debian. It is **currently dead code**: no manifest requests `--python X.Y`. Either guard it behind the distro check, or replace it with `uv python install`, which works everywhere. |
| JDK | `tools.d/base.apt:83-84` | `openjdk-21-jdk` and the `default-jdk` metapackage depend on the Debian release. **Check against the target release rather than assuming** — this is the most likely single point of failure. |
| Azure CLI | `modules/40-cloud.sh:22` | `InstallAzureCLIDeb` runs on Debian, but consults `lsb_release` internally and Microsoft's supported-suite list lags. Expect warn-and-continue on testing/sid; the module already tolerates that. |
| Archive drift | `tools.d/*.apt` | Debian stable is *older* than Ubuntu 26.04, so drift runs both directions. Packages dropped for being absent from Ubuntu's archive (`nitrogen`, `wireless-tools`, `edb-debugger`) may well exist on Debian, and current ones will be older there. |

`tests/check.sh` will not catch any of this — it validates manifest *shape*, not whether
a package name resolves in a given archive. Only a real install does that.

## Effort and noise

**Roughly 1–2 days**, and the noise is close to zero: one exported variable, at most one
small override file, and no `case` branching inside modules. The framework's apt
coupling is narrow — `apt_refresh`, `_apt_one`, `apt_install`, `ensure_python` and
`check_foreign_i386`, about 45 of 290 lines in `lib/common.sh`. Everything else
(logging, paths, arch detection, git, go, `gh_release`, venvs, assets, list reading) is
already distro-neutral.

## What "supported" would have to mean

Debian cannot honestly become a *tested* tier without a second VM in the manual
verification loop, and a second matrix leg is not a substitute — the container tier
cannot exercise the desktop, boot branding or the display manager at all. So either
commit to running `tests/verify-box.sh` on a Debian VM each release, or label it
"expected to work, untested" in the README and mean it.

## Fedora

Not planned. The cost is structural rather than incremental: a package-manager
abstraction, roughly 45 of ~125 package names renamed, about six with no Fedora
equivalent at all (`radare2`, `mdk4`, `bully`, `cowpatty`, `suckless-tools`,
`policykit-1-gnome`), and then the genuinely expensive part — `update-grub`,
`update-initramfs`, `update-alternatives`, `debconf-set-selections`,
`/etc/X11/default-display-manager`, the nginx `sites-available` layout and the GDM
dconf paths, plus SELinux as an entirely new failure class. Those live in modules 05,
06, 07 and 35, which are 48% of all module code and the *cosmetic* half of the box.

If it is ever attempted, prefer a thin `tools.d/pkgmap.dnf` carrying only the
divergences over duplicating every `.apt` manifest. Duplicated manifests are two
lockfiles where only one ever gets tested, which is worse than no port at all.

Meanwhile a Fedora user can have the whole toolkit today at zero cost to this repo:

```bash
distrobox create --image ubuntu:26.04 --name w1ld0s && distrobox enter w1ld0s
git clone https://github.com/desterhuizen/w1ld0s.git
cd w1ld0s && ./bootstrap.sh 00 10 20 30 40 50 60 70 80 90
```

The only modules that do not apply are 05/06/07/35 — exactly the ones you would not
want inside a container anyway.
