# BloodHound collection against a signing-enforced DC

The failure that motivated this whole repo. Symptom, root cause, and the routes that actually work — so it never costs an hour again.

## Symptom map

| What you see | What it means |
| --- | --- |
| `strongerAuthRequired` / `LDAPBindError` on port 389 | The DC requires LDAP signing (`Domain controller: LDAP server signing requirements = Require signing`). An unsigned simple bind is refused outright. |
| `Connection reset by peer` / `[SSL] record layer failure` on port 636 | The DC has **no LDAPS certificate**. There is no TLS to fall back to — 636 isn't really listening in a usable way. |
| `channel binding: No TLS cert` from `ldap-checker` | Same thing, stated plainly: channel binding can't be evaluated because there's no cert. |
| Both of the above at once | The trap. You can't bind unsigned on 389, and you can't do TLS on 636. Plain-LDAP collection is structurally impossible. |

Confirm it before theorising:

```bash
nxc ldap dc01.domain.local -u user -p 'Password' -M ldap-checker
ldapsearch -x -H ldap://dc01.domain.local -b '' -s base    # unauthenticated RootDSE still works
```

## Root cause

Two separate packaging problems stack up:

1. **Stock `ldap3` (2.9.1, the distro build) cannot sign.** It will negotiate SASL/GSSAPI, but it does not apply the GSS integrity (sign) or confidentiality (seal) security layer to the LDAP messages that follow. The DC sees an unsigned bind and returns `strongerAuthRequired`.
2. **Kali's `bloodhound.py` 1.x hand-rolls its Kerberos AP_REQ** and passes no security layer either — so even the Kerberos path fails for the same reason, which is what makes the error so confusing.

Layer on Kali's packaging: `netexec` hard-depends on legacy `bloodhound.py`, which collides with `bloodhound-ce`. One shared `site-packages`, one distro-chosen `ldap3`, and no way out. This is precisely why w1ld0s gives the CE ingestor its **own venv** (`modules/20-ad-network.sh`) with a sign/seal-capable `ldap3` — see `/opt/w1ld0s/venvs/bloodhound-ce`.

## Route A — Kerberos (preferred)

Kerberos binds carry their own integrity, which satisfies the signing requirement without needing TLS.

```bash
# 1. Get a TGT. Note: NO @host suffix on the principal, and NO -k on getTGT.
impacket-getTGT 'DOMAIN.LOCAL/user:Password'
#   -> writes user.ccache in $PWD

# 2. Point the GSSAPI stack at it.
export KRB5CCNAME="$PWD/user.ccache"
klist                      # verify: principal, realm, expiry

# 3. Collect with the CE ingestor from its isolated venv.
bloodhound-ce-python -d domain.local -u user -k -no-pass \
    -dc dc01.domain.local -ns <DC-IP> \
    -c All --zip
```

Two rules that cause most of the failures here:

- **Always use the FQDN**, never an IP, for anything Kerberos. The SPN is built from the name you type; an IP produces a principal the KDC has never heard of.
- **Clock skew must be under 5 minutes.** `sudo ntpdate dc01.domain.local` or `sudo chronyc makestep` against the DC before you start.

### Minimal working `krb5.conf`

```ini
[libdefaults]
    default_realm = DOMAIN.LOCAL
    dns_lookup_kdc = false
    dns_lookup_realm = false
    rdns = false

[realms]
    DOMAIN.LOCAL = {
        kdc = dc01.domain.local
        admin_server = dc01.domain.local
    }

[domain_realm]
    .domain.local = DOMAIN.LOCAL
    domain.local = DOMAIN.LOCAL
```

Realm in **UPPERCASE**, hostnames in lowercase. `rdns = false` matters on labs where reverse DNS lies.

### Service tickets

```bash
impacket-getST -spn 'cifs/dc01.domain.local' \
    -impersonate Administrator 'DOMAIN.LOCAL/user:Password'
```

## Route B — ADWS collector

If `ldap3` still refuses to sign, skip LDAP entirely. Active Directory Web Services listens on **9389** and was open in the environment that triggered this. It speaks SOAP over a different stack, so the LDAP signing policy doesn't apply.

Check first:

```bash
nmap -p 9389 -Pn dc01.domain.local
```

Then collect with an ADWS-based collector (SOAPHound or equivalent) and upload the resulting JSON to the CE host.

## Route C — Windows SharpHound

Run SharpHound from a domain-joined Windows box or a runas session. Windows' own LDAP client signs correctly by default, so the whole problem disappears. Slowest to set up, most reliable when A and B both stall.

## Uploading

BloodHound CE runs on a **separate host** in this setup — the VM only produces the JSON/zip. `~/.nxc/nxc.conf` already points at that host (migrate it via `modules/99-secrets.sh`). Upload through the CE web UI or the CE API; don't try to run the CE server on the pentest VM.

## Quick verification that the isolation worked

```bash
pipx list                                   # one venv per tool, no shared deps
/opt/w1ld0s/venvs/bloodhound-ce/bin/pip show ldap3   # should NOT be 2.9.1 distro build
bloodhound-ce-python -h                     # resolves via the shim in ~/.local/bin
nxc --version                               # netexec unaffected by the above
```

If `nxc` and `bloodhound-ce-python` can both run without one breaking the other, the core design goal of this repo is met.
