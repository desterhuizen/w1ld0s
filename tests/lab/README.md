# The scan lab

Two throwaway containers that `tests/scan-lab.sh` scans, so an upgraded tool can
be checked against something whose answers are known in advance.

**This runs on your workstation, not on the w1ld0s box.** The box is normally a
guest VM, so nesting Docker inside it would make Docker a provisioning
prerequisite for no benefit. Instead the lab publishes ports on the host and the
guest scans back to the host's address on the hypervisor network. That also means
one target IP with two service surfaces, rather than two separate hosts.

| Service | Image (digest-pinned) | Surface |
|---|---|---|
| `web` | `ghcr.io/digininja/dvwa` | Apache/PHP, `login.php`, `setup.php`, real CVE surface for nuclei |
| `dc` | `diegogslomp/samba-ad-dc` (Samba 4.24.6) | A provisioned AD domain — LDAP, Kerberos and SMB |

Domain: realm `LAB.W1LD0S.LOCAL`, NetBIOS `W1LD0S`, DC `DC1`, and an
`Administrator` account with the password in `compose.yml`. The image provisions
all of that on first start, so there is nothing to create by hand.

Two quirks the assertions in `tests/scan-lab.sh` had to be written around, both
Samba behaviour rather than tool bugs. Shares are lowercase — `sysvol`, not the
Windows `SYSVOL`. And `ldap server require strong auth` defaults to yes, so an
NTLM bind over plain LDAP is refused mid-session; `ldapdomaindump` therefore runs
with `-at SIMPLE` and the `DOMAIN\user` form.

## Two warnings worth reading before you bring it up

The DC image requires `privileged: true` — that is upstream's requirement, not
ours, and it is why this belongs on a lab host you are willing to throw away.

`W1LD0S_LAB_BIND` defaults to `127.0.0.1`, which is safe but **unreachable from
the guest**. To actually use the lab you must bind it to an interface the guest
can reach, and at that moment you are exposing a domain controller and a
deliberately vulnerable web app to whatever that interface can see. Bind it to
the hypervisor interface — never `0.0.0.0` — and bring it down when you are done.

## Bring it up

Find the host's address on the hypervisor network, on the **host**:

| Hypervisor | Command |
|---|---|
| VMware Fusion / Workstation (NAT) | `ifconfig vmnet8` — take the `inet` address |
| UTM / Apple Virtualization (shared) | `ifconfig bridge100` |
| Parallels | `ifconfig vnic0` |
| libvirt / KVM (default net) | `ip -4 addr show virbr0` |

```sh
export W1LD0S_LAB_BIND=192.168.x.1        # NOT 0.0.0.0
docker compose -f tests/lab/compose.yml up -d
docker compose -f tests/lab/compose.yml ps   # wait for dc to report (healthy)
```

The DC takes roughly half a minute to provision the forest on the very first
start. `scan-lab.sh` will tell you if it is not ready.

## Point the box at it

On the **guest**, once per VM:

```sh
echo 192.168.x.1 > tests/lab/target
./tests/scan-lab.sh -v
```

No `/etc/hosts` entry and no resolver change is needed. Every AD tool in the set
is handed the DC's address explicitly (`-dc-ip`, `--dc`, or the bare host), so
none of them ever resolves the realm — which is just as well, because publishing
the DC's port 53 would not have helped: the container's DNS answers with its own
internal address, unroutable from the guest. Kerberos-*authenticated* usage
(`-k`, a ccache) would need name resolution, but nothing here does that.

If the guest cannot reach the lab, the likeliest cause is the host firewall —
on macOS, System Settings → Network → Firewall set to "Block all incoming
connections".

## Tear it down

```sh
docker compose -f tests/lab/compose.yml down          # keeps the domain
docker compose -f tests/lab/compose.yml down -v       # forgets it; next up reprovisions
```

## Why the images are pinned by digest

Neither upstream publishes a stable semantic tag — DVWA tags every commit, and
`samba-ad-dc:latest` tracks the newest Samba release. A fixture whose surface
moves underneath you cannot answer "did my upgrade break this", so the digest is
the lockfile. This deliberately inverts the note in `tests/Dockerfile` about
leaving versions unpinned: that image is the checker's own environment, whereas
these images *are* the assertion surface.

To move to a newer fixture, resolve the new digest and change it here — the same
freeze-after-it-works discipline the `tools.d/` manifests use.
