#!/usr/bin/env bash
# tests/scan-lab.sh — run a fixed set of scans against the Docker lab and assert
# that each tool still reports the facts it is supposed to report.
#
# This is the Tier 4 entry point. Every other tier asserts that a tool is
# PRESENT; this one asserts that it still returns the right ANSWER — which is
# what you actually want to know after bumping a pin in tools.d/.
#
#   ./tests/scan-lab.sh              # every installed tool
#   ./tests/scan-lab.sh -v           # print every passing fact too
#   ./tests/scan-lab.sh nxc ffuf     # only these (prefix match)
#   ./tests/scan-lab.sh --strict     # warnings become failures
#
# The lab runs on your WORKSTATION, not here — see tests/lab/README.md for the
# compose stack, and put the host's address in tests/lab/target first.
#
# Deliberately does NOT source lib/common.sh: it dies at lib/common.sh:65-66 on
# root or missing sudo, and its warn() writes to stderr and counts nothing,
# which would silently shadow tests/lib.sh's warn() and break --strict.
#
# The rule every assertion here follows: ANCHOR ON TOKENS THE FIXTURE SUPPLIES
# (W1LD0S, DC1, login.php), NEVER ON TOKENS THE TOOL SUPPLIES. Versions, column
# widths and banner layouts all move between releases; the fixture does not.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib.sh
source "$ROOT/tests/lib.sh"
parse_flags "$@" || exit $?
cd "$ROOT" || exit 1

LAB="$ROOT/tests/lab"
GOBIN="$HOME/go/bin"
OUT="$HOME/.local/tmp/w1ld0s-scan-lab/$(date -u +%Y%m%dT%H%M%SZ)"

# pipx and go binaries are not on a non-interactive shell's PATH.
export PATH="$GOBIN:$HOME/.local/bin:$PATH"
# Colour inside a status string defeats every regex below. run_scan strips what
# leaks through anyway, but asking politely first keeps the transcripts readable.
export NO_COLOR=1

have() { command -v "$1" >/dev/null 2>&1; }

# The positional half of verify-box.sh:39's want(). The auto-detect half is
# dropped on purpose: there, a missing tool means its module never ran and
# silence is right; here it means the tool is absent or broken, which the
# operator needs to see — so tool() turns it into an explicit skip.
selected() {  # selected <name>
  [ "${#TESTS_ARGS[@]}" -eq 0 ] && return 0
  local a; for a in "${TESTS_ARGS[@]}"; do [ "${1#"$a"}" != "$1" ] && return 0; done
  return 1
}

tool() {  # tool <label> <binary-or-path> — selected AND installed; opens the section
  selected "$1" || return 1
  if [ -x "$2" ] || have "$2"; then section "$1"; return 0; fi
  skip "$1: $2 not installed"; return 1
}

# run_scan <timeout-secs> <name> <cmd...>
#
# Runs the command under `timeout`, merges stderr into stdout, strips ANSI, and
# writes the transcript to $OUT/<name>.txt. Prints NOTHING itself: the asserts
# are the report and the transcript is the artefact, so a chatty scanner can
# never bury a [FAIL] line.
#
# Sets SCAN_FILE and SCAN_RC, and ALWAYS returns 0. nmap, whatweb and nuclei all
# exit non-zero on output a human would call a success — whatweb 0.6.4 exits 1
# on a perfectly good scan — so exit status is asserted explicitly where it
# means something and never used as control flow.
run_scan() {
  local t="$1" name="$2"; shift 2
  SCAN_FILE="$OUT/$name.txt"
  # Guard against passing the arguments but forgetting the command — the
  # transcript then holds a shell error, every assertion misses, and the report
  # blames the tool. Cheap to check, and nothing static can catch it.
  if ! { [ -x "$1" ] || have "$1"; }; then
    fail "$name: '$1' is not a command — run_scan takes <timeout> <name> <cmd...>"
    : > "$SCAN_FILE"; SCAN_RC=127; return 0
  fi
  # timeout heads the pipeline, so PIPESTATUS[0] is the tool's own status
  # (124 when it was killed). The sed is smoke.yml's ANSI stripper.
  timeout -k 5 "$t" "$@" </dev/null 2>&1 | sed 's/\x1b\[[0-9;]*m//g' > "$SCAN_FILE"
  SCAN_RC="${PIPESTATUS[0]}"
  [ "$SCAN_RC" -eq 124 ] && fail "$name: timed out after ${t}s"
  return 0
}

assert_in()     { grep -qE "$2" "$SCAN_FILE" && pass "$1" || fail "$1 — /$2/ not in ${SCAN_FILE#"$HOME"/}"; }
# The discriminating half: a scanner that reports everything passes every
# positive assertion ever written.
assert_not_in() { grep -qE "$2" "$SCAN_FILE" && fail "$1 — /$2/ present in ${SCAN_FILE#"$HOME"/}" || pass "$1"; }
assert_rc()     { [ "$SCAN_RC" = "$2" ] && pass "$1" || fail "$1 — exit $SCAN_RC, expected $2"; }

# ---------------------------------------------------------------------------
# Preflight. The target is a moving part no other tier has, and it is the
# operator's own workstation — so a wrong address must produce one accurate
# message, not a dozen misleading tool failures.
section "Lab preflight"

TARGET="${W1LD0S_LAB:-}"
if [ -z "$TARGET" ] && [ -f "$LAB/target" ]; then
  TARGET="$(sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "$LAB/target" | head -1)"
fi
if [ -z "$TARGET" ]; then
  skip "no lab target — put the Docker host's address in tests/lab/target (see tests/lab/README.md)"
  summarise
fi
note "target: $TARGET"

mkdir -p "$OUT" || { fail "cannot create $OUT"; summarise; }
note "transcripts: $OUT"

tcp_open() {  # tcp_open <host> <port>
  timeout 5 bash -c 'exec 3<>"/dev/tcp/$1/$2"' _ "$1" "$2" 2>/dev/null
}

WEB_OK=1; DC_OK=1
tcp_open "$TARGET" 80  || { skip "web lab unreachable at $TARGET:80 — is the compose stack up?";  WEB_OK=0; }
tcp_open "$TARGET" 445 || { skip "dc lab unreachable at $TARGET:445 — is the compose stack up?"; DC_OK=0; }

# Liveness is not identity. Something answering on 80 or 445 that ISN'T the
# fixture is a failure with a clear cause, not a dozen confusing ones.
if [ "$WEB_OK" -eq 1 ]; then
  if curl -sf --max-time 10 "http://$TARGET/login.php" 2>/dev/null | grep -qi dvwa; then
    pass "web fixture answers as DVWA"
  else
    fail "$TARGET:80 answers but is not DVWA — something else is listening"; WEB_OK=0
  fi
fi
if [ "$DC_OK" -eq 1 ] && have ldapsearch; then
  if ldapsearch -x -H "ldap://$TARGET" -b '' -s base namingContexts 2>/dev/null \
     | grep -q 'DC=lab,DC=w1ld0s,DC=local'; then
    pass "dc fixture answers as LAB.W1LD0S.LOCAL"
  else
    fail "$TARGET:445 answers but the domain is not LAB.W1LD0S.LOCAL"; DC_OK=0
  fi
fi

# No name resolution is needed anywhere below: every AD tool here is given the
# DC's address explicitly (-dc-ip, --dc, or the bare host), so none of them ever
# resolves the realm. Kerberos-authenticated usage (-k / ccache) would need
# /etc/hosts or a resolver pointed at the DC; nothing in this set does that.

[ "$WEB_OK" -eq 1 ] || [ "$DC_OK" -eq 1 ] || summarise

WEB="http://$TARGET"

# ---------------------------------------------------------------------------
# nmap is the one tool that spans both surfaces, so it runs whenever either is
# up and asserts only the halves that are.
if tool nmap nmap; then
  # -sT because an unprivileged SYN scan needs root; --version-light keeps -sV
  # from spending a minute on the RPC ports. 64999 is the control: nothing binds
  # it, so a scanner that reports it open is broken.
  run_scan 120 nmap nmap -Pn -n -sT -sV --version-light -p 80,88,139,389,445,3268,64999 "$TARGET"
  [ "$WEB_OK" -eq 1 ] && assert_in     "nmap: 80 open"        '^80/tcp +open'
  [ "$WEB_OK" -eq 1 ] && assert_in     "nmap: identifies Apache" 'Apache'
  if [ "$DC_OK" -eq 1 ]; then
    assert_in     "nmap: 445 open"       '^445/tcp +open'
    assert_in     "nmap: 88 kerberos open" '^88/tcp +open'
    assert_in     "nmap: 389 ldap open"  '^389/tcp +open'
    # Version string is 'Samba smbd 4' — never assert the patch level, and never
    # the SERVICE column: it has been microsoft-ds and netbios-ssn across releases.
    assert_in     "nmap: identifies Samba" '[Ss]amba'
  fi
  assert_not_in "nmap: 64999 not reported open" '^64999/tcp +open'
fi

# ---------------------------------------------------------------------------
if [ "$WEB_OK" -eq 1 ]; then

# httpx is called by absolute path: the name collides with the Python HTTP
# client, which is a plausible thing to have in a venv on this box.
if tool httpx "$GOBIN/httpx"; then
  run_scan 60 httpx "$GOBIN/httpx" -u "$WEB/login.php" -json -silent -timeout 5
  assert_in "httpx: reports 200"         '"status_code": ?200'
  assert_in "httpx: fingerprints Apache"  'Apache'
  assert_in "httpx: fingerprints PHP"     'PHP'
fi

if tool ffuf "$GOBIN/ffuf"; then
  # -mc 200 binds path to status BY CONSTRUCTION, so these assertions survive
  # every output-format change ffuf has ever made. This is the pattern to copy:
  # push the fact into the tool's filter, not into the regex.
  run_scan 60 ffuf "$GOBIN/ffuf" -u "$WEB/FUZZ" -w "$LAB/words.txt" -mc 200 -t 4 -s -noninteractive
  assert_in     "ffuf: finds login.php"          '^login\.php$'
  assert_in     "ffuf: finds setup.php"          '^setup\.php$'
  assert_not_in "ffuf: does not invent findings" '^w1ld0s-no-such-path'
fi

if tool whatweb whatweb; then
  # The tool this repo is most exposed to: clone_or_pull fast-forwards the
  # checkout on EVERY provision, so it can change under you with no pin moved.
  # Output is 'HTTPServer[Debian Linux][Apache/2.4.68 (Debian)]' — two bracket
  # groups, so anchor on the Apache[..] plugin instead and never on a version.
  run_scan 90 whatweb whatweb --color=never -a 1 "$WEB/login.php"
  assert_in "whatweb: 200 OK"          '\[200 OK\]'
  assert_in "whatweb: detects Apache"  'Apache\['
  assert_in "whatweb: detects PHP"     'PHP\['
fi

if tool nuclei "$GOBIN/nuclei"; then
  # -duc stops the update check, which means nuclei needs its corpus already on
  # disk; without it it exits [FTL] "no templates provided for scan" and every
  # assertion below would fail for a reason that is not a regression.
  if [ -d "$HOME/nuclei-templates" ] || [ -d "$HOME/.local/nuclei-templates" ]; then
    run_scan 240 nuclei "$GOBIN/nuclei" -u "$WEB" -duc -ni -nc -timeout 5 -retries 1
    # Structural on purpose. The template corpus moves independently of the
    # pinned binary, so asserting a template ID or a finding count would rot
    # within weeks. What actually breaks on a nuclei upgrade is the corpus
    # failing to parse, and that is exactly what this catches.
    assert_in "nuclei: loaded its template corpus" 'Templates loaded for current scan: [1-9][0-9]*'
    assert_rc "nuclei: completed cleanly" 0
    # count_lines, not `grep -c || echo 0`: that idiom runs both sides and
    # yields a two-line "0\n0" (tests/lib.sh:44). Its pattern is a BRE.
    note "nuclei findings: $(count_lines '^\[.*\] \[' "$SCAN_FILE")"
  else
    skip "nuclei: no template corpus on disk — run 'nuclei -update-templates'"
  fi
fi

fi  # WEB_OK

# ---------------------------------------------------------------------------
if [ "$DC_OK" -eq 1 ]; then

if tool ldapsearch ldapsearch; then
  run_scan 30 ldapsearch ldapsearch -x -H "ldap://$TARGET" -b '' -s base namingContexts dnsHostName
  assert_in "ldapsearch: naming context" 'DC=lab,DC=w1ld0s,DC=local'
  assert_in "ldapsearch: DC hostname"    'dnsHostName: DC1\.lab\.w1ld0s\.local'
fi

if tool smbclient smbclient; then
  # Shares are lowercase on Samba; do not assume the Windows SYSVOL/NETLOGON.
  run_scan 45 smbclient smbclient -N -L "//$TARGET/"
  assert_in "smbclient: lists sysvol"   '^[[:space:]]*sysvol[[:space:]]+Disk'
  assert_in "smbclient: lists netlogon" '^[[:space:]]*netlogon[[:space:]]+Disk'
fi

if tool nxc nxc; then
  run_scan 90 nxc-smb nxc smb "$TARGET"
  # nxc reports the REALM here, not the NetBIOS name — the banner reads
  # (name:DC1) (domain:lab.w1ld0s.local) (signing:True). Asserting W1LD0S would
  # quietly never match.
  assert_in "nxc: names the DC"          'name:DC1'
  assert_in "nxc: names the domain"      'domain:lab\.w1ld0s\.local'
  # The docs sentence this tier exists to falsify says "signing-enforced DC".
  # Samba enforces SMB signing by default, so assert we can actually see that.
  assert_in "nxc: sees signing enforced" 'signing:True'

  # THE flagship assertion. docs/README.md's "what none of this catches" says CI
  # "can see that netexec got a venv, not that it authenticates" — this is the
  # line that stops that being true.
  run_scan 90 nxc-smb-auth nxc smb "$TARGET" -u Administrator -p 'Passw0rd!' --shares
  assert_in "nxc: authenticates over SMB" '\[\+\]'
  assert_in "nxc: enumerates sysvol"      'sysvol'

  run_scan 90 nxc-ldap nxc ldap "$TARGET" -u Administrator -p 'Passw0rd!'
  assert_in "nxc: authenticates over LDAP" '\[\+\]'
fi

# impacket installs its examples under their own script names — GetADUsers.py,
# secretsdump.py and about seventy more. There is no impacket-* prefix; that
# spelling comes from the Debian package, and this box uses pipx.
if tool impacket GetADUsers.py; then
  run_scan 90 getadusers GetADUsers.py -all "lab.w1ld0s.local/Administrator:Passw0rd!" -dc-ip "$TARGET"
  assert_in "impacket: reads the directory" 'Administrator'
  assert_in "impacket: sees krbtgt"         'krbtgt'
fi

if tool smbmap smbmap; then
  # smbmap's table wraps and its spinner writes carriage returns all over the
  # transcript, so match share and permission loosely rather than by column.
  run_scan 90 smbmap smbmap -H "$TARGET" -u Administrator -p 'Passw0rd!'
  assert_in "smbmap: sysvol readable"   'sysvol.*READ'
  assert_in "smbmap: netlogon readable" 'netlogon.*READ'
fi

if tool kerbrute "$GOBIN/kerbrute"; then
  # Kerberos pre-auth against the KDC, addressed directly — no DNS involved.
  run_scan 90 kerbrute "$GOBIN/kerbrute" userenum --dc "$TARGET" -d lab.w1ld0s.local "$LAB/users.txt"
  assert_in "kerbrute: finds Administrator" 'VALID USERNAME:.*Administrator@lab\.w1ld0s\.local'
  # The discriminating half, and the reason users.txt carries two names that do
  # not exist: a broken Kerberos path that answers "valid" to everything would
  # sail through the assertion above.
  assert_in "kerbrute: rejects the two invalid names" 'Tested 3 usernames \(1 valid\)'
fi

if tool ldapdomaindump ldapdomaindump; then
  # -at SIMPLE is load-bearing. Samba defaults to `ldap server require strong
  # auth = yes`, so ldapdomaindump's default NTLM bind is refused by the server
  # mid-session and surfaces as LDAPSessionTerminatedByServerError — a fixture
  # policy, not a broken tool. The DOMAIN\user form is required by SIMPLE.
  run_scan 120 ldapdomaindump ldapdomaindump -at SIMPLE \
    -u 'W1LD0S\Administrator' -p 'Passw0rd!' "$TARGET" -o "$OUT/ldd"
  assert_in "ldapdomaindump: binds"          '\[\+\] Bind OK'
  assert_in "ldapdomaindump: completes dump" '\[\+\] Domain dump finished'
  [ -s "$OUT/ldd/domain_users.json" ] \
    && pass "ldapdomaindump: wrote domain_users.json" \
    || fail "ldapdomaindump: no domain_users.json in $OUT/ldd"
fi

if tool enum4linux-ng enum4linux-ng; then
  run_scan 180 enum4linux-ng enum4linux-ng -A -u Administrator -p 'Passw0rd!' "$TARGET"
  assert_in "enum4linux-ng: computer name" 'NetBIOS computer name: DC1'
  assert_in "enum4linux-ng: domain name"   'NetBIOS domain name: W1LD0S'
  assert_in "enum4linux-ng: FQDN"          'FQDN: dc1\.lab\.w1ld0s\.local'
  assert_in "enum4linux-ng: confirms the credential works" \
            "Server allows authentication via username 'Administrator'"
fi

fi  # DC_OK

summarise
