#!/usr/bin/env bash
# Loads NetworkService and the Network Center VPN views inside Quickshell
# (offscreen, no compositor) and runs the checks in smoke/vpn-views.qml.
# HOME is a temporary directory with sample config files; nm-vpn and nmcli
# are stubs, so no real NetworkManager state is read or changed.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Quickshell only loads files under its config root: build one with the smoke
# shell at the top and copies of what the views import.
root="$tmp/qs"
mkdir -p "$root"
cp -r "$here/../components" "$here/../services" "$here/../theme" "$root/"
cp "$here/smoke/vpn-views.qml" "$root/shell.qml"

mkdir -p "$tmp/hm/Downloads" "$tmp/hm/Documents"
printf 'client\nremote vpn.example.com\n' > "$tmp/hm/Downloads/office.ovpn"
printf '[Interface]\n' > "$tmp/hm/Downloads/wg0.conf"
printf 'not a vpn\n' > "$tmp/hm/Documents/notes.txt"

mkdir -p "$tmp/bin"
cat > "$tmp/bin/nmcli" <<'STUB'
#!/bin/sh
# Stand-in nmcli: three saved profiles and nothing else.
printf '%s\n' "$*" >> "$NMCLI_LOG"
case "$*" in
  *"connection show"*) printf 'Office:uuid-l2tp:vpn\nHome WG:uuid-wg:wireguard\nCafe:uuid-wifi:802-11-wireless\n' ;;
esac
exit 0
STUB
cat > "$tmp/bin/nm-vpn" <<'STUB'
#!/usr/bin/env python3
# Stand-in nm-vpn: fixed answers; logs argv and the request for the checks below.
import json, os, sys
cmd = sys.argv[1] if len(sys.argv) > 1 else ""
req = json.loads(sys.stdin.read() or "{}")
with open(os.environ["NMVPN_LOG"], "a") as f:
    f.write(json.dumps({"argv": sys.argv[1:], "req": req}) + "\n")
TYPES = [{"name": "l2tp", "service": "org.freedesktop.NetworkManager.l2tp", "import": False},
         {"name": "openvpn", "service": "org.freedesktop.NetworkManager.openvpn", "import": True},
         {"name": "wireguard", "service": None, "import": True},
         {"name": "fortisslvpn", "service": "org.freedesktop.NetworkManager.fortisslvpn", "import": False}]
PROFILES = {
    "uuid-l2tp": {"uuid": "uuid-l2tp", "name": "Office", "type": "l2tp",
                  "data": {"gateway": "vpn.example.com", "user": "alice", "ipsec-enabled": "yes",
                           "password-flags": "0", "ipsec-psk-flags": "2", "lcp-echo-interval": "30"},
                  "secrets": {"password": "save", "ipsec-psk": "ask"},
                  "native": {"ipv4.never-default": "no"}, "user": {}},
    "uuid-imported": {"uuid": "uuid-imported", "name": "office", "type": "openvpn",
                      "data": {"remote": "vpn.example.com", "connection-type": "password"},
                      "secrets": {"password": "unset"}, "native": {"ipv4.never-default": "no"}, "user": {}},
}
if cmd == "types":
    out = {"ok": True, "types": TYPES}
elif cmd == "get":
    p = PROFILES.get(req.get("uuid"))
    out = {"ok": True, "profile": p} if p else {"ok": False, "error": "No VPN profile"}
elif cmd in ("add", "update"):
    out = {"ok": True, "uuid": req.get("uuid", "uuid-new")}
elif cmd == "import":
    out = {"ok": True, "uuid": "uuid-imported"}
elif cmd == "connect":
    if req.get("uuid") == "uuid-wg":
        out = {"ok": True}
    else:
        has = "ipsec-psk" in (req.get("secrets") or {})
        out = {"ok": True} if has else {"ok": False, "need": ["ipsec-psk"], "type": "l2tp"}
else:
    out = {"ok": False, "error": "usage"}
print(json.dumps(out))
STUB
chmod +x "$tmp/bin/nmcli" "$tmp/bin/nm-vpn"
: > "$tmp/nm-vpn.log"
: > "$tmp/nmcli.log"

HOME="$tmp/hm" PATH="$tmp/bin:$PATH" NMVPN_LOG="$tmp/nm-vpn.log" NMCLI_LOG="$tmp/nmcli.log" QS_NO_POLKIT_AGENT=1 \
  QT_QPA_PLATFORM=offscreen timeout 120 quickshell -p "$root/shell.qml" > "$tmp/log" 2>&1

if grep -rn "nm-connection-editor" "$here/../components" "$here/../services"; then echo "FAIL nm-connection-editor is still referenced"; exit 1; fi
grep -oE 'SMOKE (OK|FAIL|DONE).*' "$tmp/log"
fail=0
python3 - "$tmp/nm-vpn.log" "$tmp/nmcli.log" <<'PY' || fail=1
import json, sys
calls = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
bad = 0
def ok(cond, msg):
    global bad
    print(("OK   " if cond else "FAIL ") + msg)
    if not cond:
        bad += 1
ok(all("smoke-secret" not in " ".join(c["argv"]) for c in calls), "secrets never reach nm-vpn's argv")
connects = [c for c in calls if c["argv"][:1] == ["connect"]]
ok(any((c["req"].get("secrets") or {}).get("ipsec-psk") == "smoke-secret-1" for c in connects),
   "an Ask secret reaches nm-vpn on stdin")
ok(any((c["req"].get("secrets") or {}).get("ipsec-psk") == "smoke-secret-2" for c in connects),
   "the prompt's secret reaches nm-vpn on stdin")
ok(any(c["req"].get("mode") == "full" for c in connects),
   "the mode prompt's choice reaches nm-vpn")
ok(any(c["req"].get("mode") == "split" and (c["req"].get("secrets") or {}).get("ipsec-psk") == "smoke-secret-2" for c in connects),
   "the selected mode reaches the connect that carries the prompt's secret")
nmcli = open(sys.argv[2]).read().splitlines()
ok(any("connection down uuid uuid-l2tp" in l for l in nmcli),
   "an active VPN disconnects through nmcli")
imports = [c for c in calls if c["argv"][:1] == ["import"]]
ok(any(c["req"].get("type") == "openvpn" and c["req"].get("path", "").endswith("office.ovpn") for c in imports),
   "the .ovpn file is imported as openvpn")
adds = [c for c in calls if c["argv"][:1] == ["add"]]
ok(any(c["req"].get("data", {}).get("gateway") == "smoke.example.com"
       and c["req"].get("secrets", {}).get("password", {}).get("value") == "smoke-secret-3"
       and c["req"].get("data", {}).get("ipsec-enabled") == "no" for c in adds),
   "the form's add request carries its fields and the typed secret on stdin")
# --- log checks are added below by later tasks ---
sys.exit(1 if bad else 0)
PY
if ((fail)) || ! grep -q 'SMOKE DONE failures=0' "$tmp/log"; then
  echo "--- quickshell log (errors) ---"
  grep -iE 'error|warn|unavailable|cannot|failed' "$tmp/log" | head -20
  exit 1
fi
echo "OK (vpn view smoke tests)"
