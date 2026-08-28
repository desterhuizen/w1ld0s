<p align="center">
  <img src="assets/branding/w1ld0s.png" alt="w1ld0s" width="320">
</p>

<h1 align="center">w1ld0s</h1>

<p align="center"><em>Stability. Trust. Dominance.</em></p>

A clean Ubuntu 26.04 LTS pentest workstation, provisioned by one idempotent bash
script. No Kali coupling, no apt-versioned Python security tools, every Python CLI in
its own venv.

```bash
sudo apt install -y git openssh-client ca-certificates curl
git clone https://github.com/desterhuizen/w1ld0s.git
cd w1ld0s && ./bootstrap.sh
```

No SSH key and no GitHub account needed — every repo the modules clone resolves over
https. Re-runnable: modules that fail warn and continue, so you fix forward rather than
starting over.

```bash
./bootstrap.sh              # everything, in order
./bootstrap.sh 20 30        # only modules starting 20 and 30
./bootstrap.sh 20-ad-network
```

## How it fits together

| | |
|---|---|
| `bootstrap.sh` | Runs the 17 modules in order; accepts a subset by name. |
| `lib/common.sh` | The whole framework: logging, `apt_install`, `pipx_tool`, `venv_create`, `gh_release`, `clone_or_pull`. |
| `modules/` | One numbered step per domain — base, desktop, AD, web, cloud, RE, payloads, wireless. |
| `tools.d/` | Declarative, pinnable manifests. **The manifests are the lockfile.** |
| `assets/` | Dotfiles and branding copied onto the box verbatim. |
| `tests/` | `check.sh` (static checks, runs in CI and via Docker), `verify-box.sh` (asserts a provisioned box), `box-state.sh` (idempotence digest), `scan-lab.sh` (real scans against a throwaway Docker lab). |

The operator toolkit — engagement state, enumeration wrappers, cheatsheets, and the
aliases that drive them — lives in a separate repo,
[w1ld0s-tools](https://github.com/desterhuizen/w1ld0s-tools), which module 90 clones for
you. The OS changes every two years; those scripts change every week.

**[Full documentation →](docs/README.md)** — core principles, the per-module table, the
complete tool inventory, first-run procedure, pinning rules, and known gaps.

## Why not Kali

Kali makes version decisions for you and they collide. `netexec` hard-depends on legacy
`bloodhound.py`, which conflicts with `bloodhound-ce`. The distro `ldap3` ships without
a working LDAP sign/seal layer, which makes collection against a signing-enforced DC
with no LDAPS certificate structurally impossible. One shared `site-packages` plus a
distro choosing versions produces exactly that class of unexplainable breakage.

So: apt for the OS and stable native tools only, one pipx venv per Python CLI, and a
dedicated venv for anything needing patched dependencies. See
[`docs/ad-collection-cheatsheet.md`](docs/ad-collection-cheatsheet.md) for the full
post-mortem.

## License

AGPLv3 — see [LICENSE](LICENSE). Read [NOTICE](NOTICE) before use: this provisions an
offensive-security workstation, and using that tooling against systems you are not
authorized to test is a criminal offense in most jurisdictions.

Bundled fonts keep their own licenses — see
[`assets/fonts/`](assets/fonts/).
