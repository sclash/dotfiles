"""Tests for quickshell/scripts/nm-vpn.py: the pure logic, and the CLI against
the JSON-file backend (NM_VPN_FAKE_STATE) with a fake nmcli. No
NetworkManager is touched. Run: bash quickshell/tests/test-nm-vpn.sh"""
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
HELPER = os.path.join(HERE, "..", "scripts", "nm-vpn.py")
_spec = importlib.util.spec_from_file_location("nm_vpn", HELPER)
nv = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(nv)

# Records argv and the passwd-file content; fails when FAKE_NMCLI_FAIL is set.
FAKE_NMCLI = r"""#!/usr/bin/env bash
printf '%s\n' "$@" > "$FAKE_NMCLI_ARGS"
pf=""; prev=""
for a in "$@"; do [[ $prev == passwd-file ]] && pf=$a; prev=$a; done
if [[ -n $pf ]]; then cat "$pf" > "$FAKE_NMCLI_PASSWD"; else : > "$FAKE_NMCLI_PASSWD"; fi
if [[ -n ${FAKE_NMCLI_FAIL:-} ]]; then
  echo "Error: Connection activation failed: $FAKE_NMCLI_FAIL" >&2
  exit 4
fi
echo "Connection successfully activated (D-Bus active path: /x/1)"
"""


def l2tp(**over):
    rec = {"uuid": "u", "name": "Office", "type": "l2tp", "service": "org.freedesktop.NetworkManager.l2tp",
           "data": {"gateway": "g", "user": "alice", "password-flags": "0", "ipsec-psk-flags": "2"},
           "secrets": {"password": "stored-pw"}, "native": {"ipv4.never-default": "no"}, "user": {}}
    rec.update(over)
    return rec


def edit(**over):
    req = {"type": "l2tp", "name": "Office", "data": {"gateway": "g"}, "secrets": {}, "native": {}, "user": {}}
    req.update(over)
    return req


class PureLogic(unittest.TestCase):
    def test_mode_from_flags(self):
        self.assertEqual(nv.mode_from_flags(0, True), "save")
        self.assertEqual(nv.mode_from_flags(0, False), "unset")
        self.assertEqual(nv.mode_from_flags(2, True), "ask")
        self.assertEqual(nv.mode_from_flags(1, True), "ask")   # agent-owned: nothing supplies it any more
        self.assertEqual(nv.mode_from_flags(4, False), "unset")

    def test_plan_secret(self):
        self.assertEqual(nv.plan_secret("ask", "x", 0, True), (2, ""))
        self.assertEqual(nv.plan_secret("save", "pw", 2, False), (0, "pw"))
        self.assertEqual(nv.plan_secret("save", "", 0, True), (0, None))
        self.assertEqual(nv.plan_secret("save", "", 2, False), (4, ""))
        self.assertEqual(nv.plan_secret("save", "", 0, False), (4, ""))

    def test_secret_keys_come_from_flags_and_values(self):
        self.assertEqual(nv.secret_keys(l2tp()), ["ipsec-psk", "password"])
        wg = {"type": "wireguard", "data": {}, "secrets": {}, "native": {"peer.public-key": "P"}, "user": {}}
        self.assertEqual(nv.secret_keys(wg), ["wireguard.private-key", "peer.preshared-key"])

    def test_describe_never_contains_values(self):
        d = nv.describe(l2tp())
        self.assertEqual(d["secrets"], {"password": "save", "ipsec-psk": "ask"})
        self.assertNotIn("stored-pw", json.dumps(d))
        self.assertNotIn("secrets_unreadable", nv.describe(l2tp(secrets_unreadable=True)))

    def test_ask_keys(self):
        self.assertEqual(nv.ask_keys(l2tp()), ["ipsec-psk"])
        wg = {"uuid": "w", "name": "WG", "type": "wireguard", "data": {}, "secrets": {},
              "native": {"peer.public-key": "P", "wireguard.private-key-flags": "2", "peer.preshared-key-flags": "2"}, "user": {}}
        self.assertEqual(nv.ask_keys(wg), ["wireguard.private-key"])   # a peer PSK is never asked

    def test_apply_keeps_flags_and_removes_absent_data(self):
        rec = nv.apply_request(l2tp(), edit(name="Office 2"))
        self.assertEqual(rec["name"], "Office 2")
        self.assertNotIn("user", rec["data"])
        self.assertEqual(rec["data"]["password-flags"], "0")
        self.assertEqual(rec["data"]["ipsec-psk-flags"], "2")
        self.assertEqual(rec["secrets"], {"password": "stored-pw"})   # secrets left out are kept

    def test_apply_secret_modes(self):
        rec = nv.apply_request(l2tp(), edit(secrets={"password": {"mode": "ask", "value": ""},
                                                     "ipsec-psk": {"mode": "save", "value": "psk"}}))
        self.assertEqual(rec["data"]["password-flags"], "2")
        self.assertNotIn("password", rec["secrets"])
        self.assertEqual(rec["data"]["ipsec-psk-flags"], "0")
        self.assertEqual(rec["secrets"]["ipsec-psk"], "psk")

    def test_apply_wireguard_multi_peer_keeps_peers(self):
        rec = {"uuid": "w", "name": "WG", "type": "wireguard", "service": None, "data": {}, "secrets": {"wireguard.private-key": "K"},
               "native": {"peer.count": "2", "peer.public-key": "P1", "connection.interface-name": "wg0",
                          "wireguard.private-key-flags": "0", "ipv4.addresses": "10.0.0.2/32"}, "user": {}}
        req = {"type": "wireguard", "name": "WG2", "data": {}, "secrets": {},
               "native": {"ipv4.addresses": "10.0.0.3/32", "peer.public-key": "OTHER"}, "user": {}}
        out = nv.apply_request(rec, req)
        self.assertEqual(out["native"]["peer.public-key"], "P1")
        self.assertEqual(out["native"]["peer.count"], "2")
        self.assertEqual(out["native"]["connection.interface-name"], "wg0")
        self.assertEqual(out["native"]["ipv4.addresses"], "10.0.0.3/32")
        self.assertEqual(out["secrets"]["wireguard.private-key"], "K")

    def test_apply_rejects_unknown_wireguard_secret(self):
        rec = {"uuid": "w", "name": "WG", "type": "wireguard", "service": None, "data": {}, "secrets": {}, "native": {}, "user": {}}
        with self.assertRaises(nv.Failure):
            nv.apply_request(rec, {"type": "wireguard", "name": "WG", "data": {}, "native": {}, "user": {},
                                   "secrets": {"password": {"mode": "save", "value": "x"}}})

    def test_passwd_lines(self):
        self.assertEqual(nv.passwd_lines(l2tp(), {"ipsec-psk": "a:b"}), "vpn.secrets.ipsec-psk:a:b\n")
        wg = {"type": "wireguard"}
        self.assertEqual(nv.passwd_lines(wg, {"wireguard.private-key": "K"}), "wireguard.private-key:K\n")
        with self.assertRaises(nv.Failure):
            nv.passwd_lines(l2tp(), {"ipsec-psk": "two\nlines"})

    def test_scrub_and_nmcli_message(self):
        self.assertEqual(nv.scrub("bad pw and pw2", ["pw", "pw2"]), "bad *** and ***")
        self.assertEqual(nv.nmcli_message("Warning: x\nError: Connection activation failed: boom\n"),
                         "Connection activation failed: boom")
        self.assertEqual(nv.nmcli_message(""), "")

    def test_wg_ifname_and_split_list(self):
        self.assertEqual(nv.wg_ifname("Home VPN (laptop)"), "wg-homevpnlapto")   # 12 characters after "wg-"
        self.assertLessEqual(len(nv.wg_ifname("x" * 40)), 15)
        self.assertEqual(nv.wg_ifname("!!!"), "wg-vpn")
        self.assertEqual(nv.split_list("10.0.0.2/32, fd00::2/128  1.1.1.1"), ["10.0.0.2/32", "fd00::2/128", "1.1.1.1"])

    def test_parse_edit_validation(self):
        with self.assertRaises(nv.Failure):
            nv.parse_edit({"type": "l2tp"}, False)                          # no name
        with self.assertRaises(nv.Failure):
            nv.parse_edit(edit(user={"color": "red"}), False)               # user keys need quickshell.
        with self.assertRaises(nv.Failure):
            nv.parse_edit(edit(data={"bad key": "x"}), False)
        with self.assertRaises(nv.Failure):
            nv.parse_edit(edit(secrets={"password": {"mode": "maybe", "value": ""}}), False)
        ok = nv.parse_edit(edit(data={"form:main:group": "staff"}), False)
        self.assertEqual(ok["data"]["form:main:group"], "staff")


class Cli(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        d = self.tmp.name
        self.state = os.path.join(d, "state.json")
        with open(self.state, "w") as f:
            json.dump({
                "types": [
                    {"name": "l2tp", "service": "org.freedesktop.NetworkManager.l2tp", "import": False},
                    {"name": "openvpn", "service": "org.freedesktop.NetworkManager.openvpn", "import": True},
                    {"name": "wireguard", "service": None, "import": True},
                ],
                "profiles": {"u-office": {k: v for k, v in l2tp(secrets={"password": "stored-pw-1"}).items() if k != "uuid"}},
                "imports": {"office.ovpn": {"name": "office", "type": "openvpn", "service": "org.freedesktop.NetworkManager.openvpn",
                                            "data": {"remote": "ovpn.example.com", "connection-type": "password"},
                                            "secrets": {}, "native": {}, "user": {}}},
            }, f)
        self.ovpn = os.path.join(d, "office.ovpn")
        with open(self.ovpn, "w") as f:
            f.write("client\n")
        self.nmcli = os.path.join(d, "nmcli")
        with open(self.nmcli, "w") as f:
            f.write(FAKE_NMCLI)
        os.chmod(self.nmcli, 0o755)
        self.args_file = os.path.join(d, "nmcli-args")
        self.passwd_file = os.path.join(d, "nmcli-passwd")
        self.env = dict(os.environ, NM_VPN_FAKE_STATE=self.state, NM_VPN_NMCLI_BIN=self.nmcli,
                        FAKE_NMCLI_ARGS=self.args_file, FAKE_NMCLI_PASSWD=self.passwd_file)
        self.env.pop("FAKE_NMCLI_FAIL", None)

    def tearDown(self):
        self.tmp.cleanup()

    def stored(self, uuid):
        with open(self.state) as f:
            return json.load(f)["profiles"][uuid]

    def run_cli(self, cmd, req, **extra):
        p = subprocess.run([sys.executable, "-I", HELPER, cmd], input=req if isinstance(req, str) else json.dumps(req),
                           env=dict(self.env, **extra), capture_output=True, text=True, timeout=30)
        lines = [ln for ln in p.stdout.splitlines() if ln.strip()]
        self.assertEqual(len(lines), 1, p.stdout + p.stderr)
        self.assertEqual(p.returncode, 0, p.stderr)
        return json.loads(lines[0])

    def test_types(self):
        r = self.run_cli("types", {})
        self.assertTrue(r["ok"])
        self.assertEqual([t["name"] for t in r["types"]], ["l2tp", "openvpn", "wireguard"])

    def test_get_never_returns_secret_values(self):
        r = self.run_cli("get", {"uuid": "u-office"})
        self.assertEqual(r["profile"]["secrets"], {"password": "save", "ipsec-psk": "ask"})
        self.assertNotIn("stored-pw-1", json.dumps(r))

    def test_get_unknown_uuid(self):
        r = self.run_cli("get", {"uuid": "nope"})
        self.assertFalse(r["ok"])
        self.assertIn("No VPN profile", r["error"])

    def test_add_then_store(self):
        r = self.run_cli("add", edit(name="New", secrets={"password": {"mode": "save", "value": "new-pw-2"},
                                                          "ipsec-psk": {"mode": "ask", "value": ""}}))
        self.assertEqual(r, {"ok": True, "uuid": "fake-2"})
        s = self.stored("fake-2")
        self.assertEqual(s["data"]["password-flags"], "0")
        self.assertEqual(s["data"]["ipsec-psk-flags"], "2")
        self.assertEqual(s["secrets"], {"password": "new-pw-2"})

    def test_add_empty_save_is_not_required(self):
        self.run_cli("add", edit(secrets={"password": {"mode": "save", "value": ""}}))
        self.assertEqual(self.stored("fake-2")["data"]["password-flags"], "4")

    def test_add_unknown_type(self):
        r = self.run_cli("add", edit(type="fortisslvpn"))
        self.assertFalse(r["ok"])
        self.assertIn("not installed", r["error"])

    def test_update_empty_secret_keeps_stored(self):
        r = self.run_cli("update", edit(uuid="u-office", name="Renamed", secrets={"password": {"mode": "save", "value": ""}}))
        self.assertTrue(r["ok"], r)
        s = self.stored("u-office")
        self.assertEqual(s["name"], "Renamed")
        self.assertEqual(s["secrets"]["password"], "stored-pw-1")
        self.assertNotIn("user", s["data"])          # left out → removed
        self.assertIn("ipsec-psk-flags", s["data"])  # flags are never dropped

    def test_update_to_ask_drops_stored(self):
        self.run_cli("update", edit(uuid="u-office", secrets={"password": {"mode": "ask", "value": ""}}))
        s = self.stored("u-office")
        self.assertEqual(s["data"]["password-flags"], "2")
        self.assertNotIn("password", s["secrets"])

    def test_update_refuses_when_secrets_unreadable(self):
        with open(self.state) as f:
            st = json.load(f)
        st["profiles"]["u-office"]["secrets_unreadable"] = True
        with open(self.state, "w") as f:
            json.dump(st, f)
        before = self.stored("u-office")
        r = self.run_cli("update", edit(uuid="u-office", name="Renamed"))
        self.assertFalse(r["ok"])
        self.assertIn("Could not read the profile's saved secrets; nothing was changed. Try again.", r["error"])
        self.assertEqual(self.stored("u-office"), before)
        g = self.run_cli("get", {"uuid": "u-office"})     # get stays usable, key not leaked
        self.assertTrue(g["ok"], g)
        self.assertNotIn("secrets_unreadable", json.dumps(g))

    def test_update_type_mismatch(self):
        r = self.run_cli("update", edit(uuid="u-office", type="openvpn"))
        self.assertFalse(r["ok"])

    def test_import(self):
        r = self.run_cli("import", {"type": "openvpn", "path": self.ovpn})
        self.assertTrue(r["ok"], r)
        self.assertEqual(self.stored(r["uuid"])["type"], "openvpn")

    def test_import_missing_file(self):
        r = self.run_cli("import", {"type": "openvpn", "path": self.ovpn + ".nope"})
        self.assertFalse(r["ok"])
        self.assertIn("No such file", r["error"])

    def test_connect_needs_ask_secrets_first(self):
        r = self.run_cli("connect", {"uuid": "u-office"})
        self.assertEqual(r, {"ok": False, "need": ["ipsec-psk"], "type": "l2tp"})
        self.assertFalse(os.path.exists(self.args_file))   # nmcli never ran

    def test_connect_passes_secrets_on_a_pipe(self):
        r = self.run_cli("connect", {"uuid": "u-office", "secrets": {"ipsec-psk": "psk-secret-3"}})
        self.assertEqual(r, {"ok": True})
        with open(self.args_file) as f:
            args = f.read()
        self.assertNotIn("psk-secret-3", args)
        self.assertIn("passwd-file", args)
        self.assertIn("u-office", args)
        with open(self.passwd_file) as f:
            self.assertEqual(f.read(), "vpn.secrets.ipsec-psk:psk-secret-3\n")

    def test_connect_without_ask_secrets_has_no_passwd_file(self):
        self.run_cli("update", edit(uuid="u-office", secrets={"ipsec-psk": {"mode": "save", "value": "p"}}))
        self.assertEqual(self.run_cli("connect", {"uuid": "u-office"}), {"ok": True})
        with open(self.args_file) as f:
            self.assertNotIn("passwd-file", f.read())

    def test_connect_error_is_scrubbed(self):
        r = self.run_cli("connect", {"uuid": "u-office", "secrets": {"ipsec-psk": "psk-secret-3"}},
                         FAKE_NMCLI_FAIL="rejected psk-secret-3")
        self.assertFalse(r["ok"])
        self.assertEqual(r["error"], "Connection activation failed: rejected ***")

    def test_bad_json(self):
        r = self.run_cli("get", "not json")
        self.assertFalse(r["ok"])
        self.assertIn("not JSON", r["error"])

    def test_usage(self):
        p = subprocess.run([sys.executable, "-I", HELPER], input="", env=self.env, capture_output=True, text=True, timeout=30)
        self.assertEqual(p.returncode, 2)
        self.assertFalse(json.loads(p.stdout.strip())["ok"])


if __name__ == "__main__":
    unittest.main()
