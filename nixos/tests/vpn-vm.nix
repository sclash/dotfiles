# NixOS VM test for nm-vpn against a real NetworkManager with the repo's VPN
# plugins (spec §14): libnm round-trips for every type, import, Save/Ask
# flags, passwd-file through a pipe, and charon-nm beside services.strongswan.
# Run by nixos/tests/test-vpn-vm.sh (needs KVM). Every value is a dummy.
{ pkgs, plugins, strongswanConf }:
let
  nm-vpn = import ../../quickshell/scripts/nm-vpn.nix { inherit pkgs; };
in
pkgs.testers.runNixOSTest {
  name = "nm-vpn";
  nodes.machine = { ... }: {
    networking.networkmanager.enable = true;
    networking.networkmanager.plugins = plugins;
    services.strongswan.enable = true;
    # from the evaluated system, as plugins: charon-nm needs this file
    environment.etc."strongswan.conf".text = strongswanConf;
    users.users.alice = { isNormalUser = true; extraGroups = [ "networkmanager" ]; };
    environment.systemPackages = [ nm-vpn pkgs.wireguard-tools pkgs.xvfb ];
    environment.etc."vpn-test/office.ovpn".text = ''
      client
      dev tun
      proto udp
      remote vpn.example.invalid 1194
      auth-user-pass
      ca ca.crt
    '';
    # The OpenVPN importer refuses a file without --ca; the path is only stored.
    environment.etc."vpn-test/ca.crt".text = "dummy CA, never used\n";
  };
  testScript = ''
    import json, shlex

    def vpn(cmd, req, env=""):
        line = "printf %s " + shlex.quote(json.dumps(req)) + " | su alice -s /bin/sh -c " + shlex.quote(env + " nm-vpn " + cmd)
        out = machine.succeed(line)
        lines = [l for l in out.splitlines() if l.strip()]
        assert len(lines) == 1, out
        return json.loads(lines[0])

    def ok(r):
        assert r.get("ok") is True, r
        return r

    def secrets_of(uuid):
        return machine.succeed(f"nmcli -s -g vpn.secrets connection show uuid {uuid}")

    machine.wait_for_unit("NetworkManager.service")
    machine.wait_until_succeeds("nmcli general status")

    with subtest("types lists the plugins and WireGuard"):
        t = {x["name"]: x for x in ok(vpn("types", {}))["types"]}
        for name in ("openvpn", "l2tp", "strongswan", "wireguard"):
            assert name in t, t
        assert t["openvpn"]["import"], t
        print("VM FINDING types: " + json.dumps(t))

    def roundtrip(type_name, data, key):
        req = {"type": type_name, "name": "t-" + type_name, "data": data,
               "secrets": {key: {"mode": "save", "value": "dummy-" + type_name}},
               "native": {"ipv4.never-default": "yes"}, "user": {"quickshell.vpn.test": "1"}}
        uuid = ok(vpn("add", req))["uuid"]
        p = ok(vpn("get", {"uuid": uuid}))["profile"]
        assert p["type"] == type_name, p
        for k, v in data.items():
            assert p["data"].get(k) == v, (k, p)
        assert p["secrets"].get(key) == "save", p
        assert "dummy-" not in json.dumps(p), p
        assert p["native"].get("ipv4.never-default") == "yes", p
        assert p["user"].get("quickshell.vpn.test") == "1", p
        assert "dummy-" + type_name in secrets_of(uuid)
        # an empty value keeps the stored secret
        req.update(uuid=uuid, name="t2-" + type_name, secrets={key: {"mode": "save", "value": ""}}, native={"ipv4.never-default": "no"})
        ok(vpn("update", req))
        assert "dummy-" + type_name in secrets_of(uuid)
        assert machine.succeed(f"nmcli -g connection.id connection show uuid {uuid}").strip() == "t2-" + type_name
        assert machine.succeed(f"nmcli -g ipv4.never-default connection show uuid {uuid}").strip() == "no"
        # switching to Ask writes flags 2 and drops the value
        req.update(secrets={key: {"mode": "ask", "value": ""}})
        ok(vpn("update", req))
        p = ok(vpn("get", {"uuid": uuid}))["profile"]
        assert p["secrets"][key] == "ask", p
        assert p["data"].get(key + "-flags") == "2", p
        assert "dummy-" + type_name not in secrets_of(uuid)
        return uuid

    with subtest("L2TP round-trip"):
        roundtrip("l2tp", {"gateway": "l2tp.example.invalid", "user": "alice", "ipsec-enabled": "yes"}, "password")
    with subtest("OpenVPN round-trip"):
        ovpn = roundtrip("openvpn", {"remote": "ovpn.example.invalid", "connection-type": "password", "username": "alice"}, "password")
    with subtest("strongSwan round-trip"):
        sw = roundtrip("strongswan", {"address": "ike.example.invalid", "method": "eap", "user": "alice", "virtual": "yes"}, "password")

    with subtest("OpenVPN import"):
        uuid = ok(vpn("import", {"type": "openvpn", "path": "/etc/vpn-test/office.ovpn"}))["uuid"]
        p = ok(vpn("get", {"uuid": uuid}))["profile"]
        assert p["type"] == "openvpn" and "vpn.example.invalid" in p["data"].get("remote", ""), p
        print("VM FINDING imported openvpn: " + json.dumps(p))
        # imports are created with autoconnect off, like added profiles
        assert machine.succeed(f"nmcli -g connection.autoconnect connection show uuid {uuid}").strip() == "no"
        # the importer marks challenge-response Ask, but without a static-challenge it is never asked
        r = vpn("connect", {"uuid": uuid})
        assert r == {"ok": False, "need": ["password"], "type": "openvpn"}, r
        # a profile with no stored secrets can still be edited (secrets read as empty)
        ok(vpn("update", {"uuid": uuid, "type": "openvpn", "name": "office-renamed", "secrets": {}, "native": {}, "user": {},
                          "data": {k: v for k, v in p["data"].items() if not k.endswith("-flags")}}))
        p2 = ok(vpn("get", {"uuid": uuid}))["profile"]
        assert p2["name"] == "office-renamed" and p2["secrets"] == p["secrets"] and p2["data"] == p["data"], (p, p2)

    with subtest("WireGuard add, import and several peers"):
        key = machine.succeed("wg genkey").strip()
        pub = machine.succeed(f"echo {key} | wg pubkey").strip()
        peer2 = machine.succeed("wg genkey | wg pubkey").strip()
        uuid = ok(vpn("add", {"type": "wireguard", "name": "wg-add", "data": {}, "user": {},
            "secrets": {"wireguard.private-key": {"mode": "save", "value": key}},
            "native": {"ipv4.addresses": "10.9.0.2/32, fd09::2/128", "ipv4.dns": "10.9.0.1", "peer.public-key": pub,
                       "peer.endpoint": "192.0.2.1:51820", "peer.allowed-ips": "0.0.0.0/0", "ipv4.never-default": "no"}}))["uuid"]
        p = ok(vpn("get", {"uuid": uuid}))["profile"]
        assert p["native"]["peer.public-key"] == pub, p
        assert "10.9.0.2/32" in p["native"]["ipv4.addresses"] and "fd09::2/128" in p["native"]["ipv4.addresses"], p
        assert p["secrets"]["wireguard.private-key"] == "save", p
        assert key not in json.dumps(p)
        # Ask writes private-key-flags 2 (a GFlags property set from an int) and drops the key
        ok(vpn("update", {"uuid": uuid, "type": "wireguard", "name": "wg-add", "data": {}, "user": {},
            "secrets": {"wireguard.private-key": {"mode": "ask", "value": ""}}, "native": p["native"]}))
        p = ok(vpn("get", {"uuid": uuid}))["profile"]
        assert p["secrets"]["wireguard.private-key"] == "ask", p
        assert machine.succeed(f"nmcli -g wireguard.private-key-flags connection show uuid {uuid}").strip().startswith("2"), p
        assert key not in machine.succeed(f"nmcli -s -g wireguard.private-key connection show uuid {uuid}")
        assert vpn("connect", {"uuid": uuid}) == {"ok": False, "need": ["wireguard.private-key"], "type": "wireguard"}
        conf = "[Interface]\nPrivateKey = %s\nAddress = 10.8.0.2/32\n\n[Peer]\nPublicKey = %s\nAllowedIPs = 10.8.0.0/24\nEndpoint = 192.0.2.2:51820\n\n[Peer]\nPublicKey = %s\nAllowedIPs = 10.7.0.0/24\nEndpoint = 192.0.2.3:51820\n" % (key, pub, peer2)
        machine.succeed("printf %s " + shlex.quote(conf) + " > /tmp/two.conf && chmod 644 /tmp/two.conf")
        uuid2 = ok(vpn("import", {"type": "wireguard", "path": "/tmp/two.conf"}))["uuid"]
        p = ok(vpn("get", {"uuid": uuid2}))["profile"]
        assert p["native"]["peer.count"] == "2", p
        assert machine.succeed(f"nmcli -g connection.autoconnect connection show uuid {uuid2}").strip() == "no"
        ok(vpn("update", {"uuid": uuid2, "type": "wireguard", "name": "wg-renamed", "data": {}, "secrets": {}, "user": {},
                          "native": {"ipv4.addresses": "10.8.0.2/32", "ipv4.never-default": "no"}}))
        # this nmcli prints every peer on one line: "KEY allowed-ips=... endpoint=..., KEY ..."
        peers = machine.succeed(f"nmcli -g wireguard.peers connection show uuid {uuid2} | grep -o 'endpoint=' | wc -l").strip()
        assert peers == "2", peers

    with subtest("connect: the need handshake, then secrets through a passwd-file pipe"):
        r = vpn("connect", {"uuid": ovpn})
        assert r == {"ok": False, "need": ["password"], "type": "openvpn"}, r
        plain = machine.fail(f"su alice -s /bin/sh -c 'nmcli --wait 15 connection up uuid {ovpn}' 2>&1")
        piped = machine.fail("su alice -s /run/current-system/sw/bin/bash -c " + shlex.quote(
            f"nmcli --wait 15 connection up uuid {ovpn} passwd-file <(printf 'vpn.secrets.password:dummy\\n')") + " 2>&1")
        print("VM FINDING passwd-file without: " + plain.strip())
        print("VM FINDING passwd-file via pipe: " + piped.strip())
        assert "Secrets were required" not in piped, piped
        r = vpn("connect", {"uuid": ovpn, "secrets": {"password": "dummy-pipe-secret"}}, env="NM_VPN_CONNECT_WAIT=15")
        print("VM FINDING nm-vpn connect openvpn: " + json.dumps(r))
        assert r["ok"] is False and "Secrets were required" not in r["error"], r
        assert "dummy-pipe-secret" not in json.dumps(r), r

    with subtest("charon-nm runs beside services.strongswan"):
        machine.succeed("systemctl is-active strongswan.service")
        machine.execute("bash -c " + shlex.quote(
            f"nmcli --wait 15 connection up uuid {sw} passwd-file <(printf 'vpn.secrets.password:dummy\\n')"))
        jlog = machine.succeed("journalctl -b --no-pager | grep -iE 'charon-nm|charon|strongswan' || true")
        print("VM FINDING strongswan log tail: " + "\n".join(jlog.splitlines()[-15:]))
        assert "charon-nm" in jlog and "abort initialization" not in jlog, jlog
        assert "Address already in use" not in jlog, jlog
        assert "unable to bind" not in jlog.lower(), jlog
        machine.succeed("systemctl is-active strongswan.service")

    with subtest("L2TP/IPsec gets past IKEv1 (strongSwan built with --enable-ikev1)"):
        l2 = ok(vpn("add", {"type": "l2tp", "name": "t-l2tp-ipsec",
            "data": {"gateway": "192.0.2.10", "user": "alice", "ipsec-enabled": "yes"},
            "secrets": {"password": {"mode": "save", "value": "dummy-l2tp-pw"},
                        "ipsec-psk": {"mode": "save", "value": "dummy-l2tp-psk"}},
            "native": {"ipv4.never-default": "no"}, "user": {}}))["uuid"]
        since = machine.succeed("date '+%Y-%m-%d %H:%M:%S'").strip()
        machine.execute(f"nmcli --wait 20 connection up uuid {l2}")
        ike = machine.succeed(f"journalctl --since '{since}' --no-pager | grep -iE 'charon|ipsec|l2tp' || true")
        print("VM FINDING l2tp ipsec log tail: " + "\n".join(ike.splitlines()[-12:]))
        assert "IKE version 1 not supported" not in ike, ike
        assert "Main Mode" in ike, ike          # charon really starts an IKEv1 negotiation
        assert "dummy-l2tp-psk" not in ike and "dummy-l2tp-pw" not in ike, "secret in journal"

    with subtest("strongSwan Ask secret through nm-vpn, with a display"):
        # nm-strongswan-auth-dialog calls gtk_init before reading
        # --external-ui-mode, so nmcli only learns the secret names when a
        # display exists (as in the desktop session); without one it falls
        # back to names that miss "password" and NM reports "No valid secrets".
        machine.succeed("Xvfb :99 -ac >/dev/null 2>&1 &")
        machine.wait_until_succeeds("test -e /tmp/.X11-unix/X99")
        r = vpn("connect", {"uuid": sw, "secrets": {"password": "dummy-sw-secret"}}, env="DISPLAY=:99 NM_VPN_CONNECT_WAIT=20")
        print("VM FINDING nm-vpn connect strongswan: " + json.dumps(r))
        assert r["ok"] is False and "secrets" not in r["error"].lower(), r
        assert "dummy-sw-secret" not in json.dumps(r), r
  '';
}
