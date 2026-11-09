"""nm-vpn: VPN profiles for the Quickshell Network Center (NetworkService.qml).

    nm-vpn types|get|add|update|import|connect   < one JSON request on stdin

Prints exactly one JSON line: {"ok": true, ...} or {"ok": false, "error": ...}.
`connect` answers {"ok": false, "need": [keys], "type": t} while secrets set to
Ask are missing. Secrets travel only on stdin and, when connecting, through
nmcli's passwd-file on a pipe: never in argv, the environment or the output.
Reads and writes go through libnm (PyGObject) over D-Bus; connecting runs
`nmcli connection up uuid U passwd-file /dev/fd/N`, which makes nmcli a
one-shot secret agent for that activation.

Secret flags (NMSettingSecretFlags): 1 agent-owned, 2 not saved, 4 not
required. Save writes 0 (4 when there is no value), Ask writes 2. Flags 1 or 2
read as "ask": with nm-applet gone nothing else can supply them.

Test hooks (tests only): NM_VPN_FAKE_STATE=<json file> replaces libnm with a
JSON-file backend; NM_VPN_NMCLI_BIN overrides nmcli; NM_VPN_CONNECT_WAIT
overrides the 90 s activation wait.

Spec: quickshell/docs/superpowers/specs/2026-11-09-native-vpn-design.md
"""

import json
import os
import re
import socket
import subprocess
import sys

FLAG_AGENT_OWNED = 1
FLAG_NOT_SAVED = 2
FLAG_NOT_REQUIRED = 4
ASK_FLAGS = FLAG_AGENT_OWNED | FLAG_NOT_SAVED
WIREGUARD = "wireguard"
WG_SECRETS = ("wireguard.private-key", "peer.preshared-key")
WG_ASKABLE = ("wireguard.private-key",)
NATIVE_KEEP = ("peer.count", "connection.interface-name")
MAX_PASSWD_BYTES = 60000
KEY_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.:+-]*$")


class Failure(Exception):
    """A problem to report as {"ok": false, "error": ...}."""


# ---------- pure logic (tests/test_nm_vpn.py) ----------

def scrub(text, secrets):
    """Replace every secret in text with ***, longest first."""
    out = text or ""
    for s in sorted({s for s in secrets if s}, key=len, reverse=True):
        out = out.replace(s, "***")
    return out


def request_secrets(req):
    """Every secret value in a request (add/update objects or connect strings)."""
    secrets = req.get("secrets") if isinstance(req, dict) else None
    if not isinstance(secrets, dict):
        return []
    out = []
    for v in secrets.values():
        if isinstance(v, dict):
            v = v.get("value", "")
        if isinstance(v, str) and v:
            out.append(v)
    return out


def mode_from_flags(flags, stored):
    if flags & ASK_FLAGS:
        return "ask"
    return "save" if stored else "unset"


def plan_secret(mode, value, current_flags, has_stored):
    """(flags, value) to write for one requested secret. value None keeps the
    stored one; "" removes it."""
    if mode == "ask":
        return FLAG_NOT_SAVED, ""
    if value:
        return 0, value
    if has_stored and not current_flags & ASK_FLAGS:
        return 0, None
    return FLAG_NOT_REQUIRED, ""


def _flags_place(rec, key):
    return ("native" if rec["type"] == WIREGUARD else "data"), key + "-flags"


def get_flags(rec, key):
    section, fkey = _flags_place(rec, key)
    try:
        return int(rec[section].get(fkey, "0") or 0)
    except ValueError:
        return 0


def set_flags(rec, key, flags):
    section, fkey = _flags_place(rec, key)
    rec[section][fkey] = str(flags)


def secret_keys(rec):
    """Every secret a profile has: WireGuard's fixed ones, or each plugin key K
    with a K-flags data item or a stored value."""
    if rec["type"] == WIREGUARD:
        keys = ["wireguard.private-key"]
        if rec["native"].get("peer.public-key"):
            keys.append("peer.preshared-key")
        return keys
    keys = {k[: -len("-flags")] for k in rec["data"] if k.endswith("-flags")}
    keys.update(rec["secrets"])
    return sorted(keys)


def describe(rec):
    """A profile for `get`: settings and secret modes, never secret values."""
    secrets = {k: mode_from_flags(get_flags(rec, k), bool(rec["secrets"].get(k))) for k in secret_keys(rec)}
    native = {k: v for k, v in rec["native"].items() if not k.endswith("-flags")}
    return {"uuid": rec["uuid"], "name": rec["name"], "type": rec["type"], "data": dict(rec["data"]),
            "secrets": secrets, "native": native, "user": dict(rec["user"])}


def ask_keys(rec):
    """Secrets a connect must be given (a WireGuard peer PSK is never asked)."""
    keys = [k for k, m in describe(rec)["secrets"].items() if m == "ask"]
    if rec["type"] == WIREGUARD:
        keys = [k for k in keys if k in WG_ASKABLE]
    return sorted(keys)


def apply_request(rec, req):
    """Merge a parsed add/update request into rec (mutated and returned).
    Data keys left out are removed, except *-flags; secrets left out are kept;
    a WireGuard profile with more than one peer keeps its peers."""
    rec["name"] = req["name"]
    if rec["type"] == WIREGUARD:
        multi = int(rec["native"].get("peer.count") or 0) > 1
        native = {k: v for k, v in rec["native"].items()
                  if k.endswith("-flags") or k in NATIVE_KEEP or (multi and k.startswith("peer."))}
        native.update({k: v for k, v in req["native"].items() if not (multi and k.startswith("peer."))})
        rec["native"] = native
    else:
        data = {k: v for k, v in rec["data"].items() if k.endswith("-flags")}
        data.update(req["data"])
        rec["data"] = data
        rec["native"] = dict(req["native"])
    rec["user"].update(req["user"])
    for key, s in req["secrets"].items():
        if rec["type"] == WIREGUARD and key not in WG_SECRETS:
            raise Failure("unknown WireGuard secret %s" % key)
        mode = "save" if key == "peer.preshared-key" else s["mode"]
        flags, value = plan_secret(mode, s["value"], get_flags(rec, key), bool(rec["secrets"].get(key)))
        set_flags(rec, key, flags)
        if value is None:
            continue
        if value:
            rec["secrets"][key] = value
        else:
            rec["secrets"].pop(key, None)
    return rec


def new_record(req, service):
    rec = {"uuid": None, "name": "", "type": req["type"], "service": service,
           "data": {}, "secrets": {}, "native": {}, "user": {}}
    return apply_request(rec, req)


def passwd_lines(rec, secrets):
    """nmcli passwd-file content for the given secrets."""
    out = []
    for key in sorted(secrets):
        value = secrets[key]
        if "\n" in value or "\r" in value:
            raise Failure("A secret cannot contain a line break")
        if rec["type"] == WIREGUARD:
            if key not in WG_ASKABLE:
                raise Failure("%s cannot be given when connecting" % key)
            out.append("%s:%s\n" % (key, value))
        else:
            out.append("vpn.secrets.%s:%s\n" % (key, value))
    return "".join(out)


def nmcli_message(text):
    """The most useful line of nmcli's output, without the "Error:" prefix."""
    lines = [ln.strip() for ln in (text or "").splitlines() if ln.strip()]
    errors = [ln for ln in lines if ln.startswith("Error:")]
    msg = errors[-1] if errors else (lines[-1] if lines else "")
    return msg[len("Error:"):].strip() if msg.startswith("Error:") else msg


def split_list(text):
    return [p for p in re.split(r"[,\s]+", text or "") if p]


def wg_ifname(name):
    """An interface name for a new WireGuard profile (at most 15 characters)."""
    base = re.sub(r"[^a-z0-9]", "", (name or "").lower())[:12]
    return "wg-" + (base or "vpn")


def need_str(req, key):
    v = req.get(key)
    if not isinstance(v, str) or not v.strip():
        raise Failure("missing %s" % key)
    return v.strip()


def str_map(value, what):
    if value is None:
        return {}
    if not isinstance(value, dict) or not all(isinstance(k, str) and isinstance(v, str) for k, v in value.items()):
        raise Failure("%s must map strings to strings" % what)
    return dict(value)


def parse_edit(req, need_uuid):
    out = {"type": need_str(req, "type"), "name": need_str(req, "name")}
    if need_uuid:
        out["uuid"] = need_str(req, "uuid")
    out["data"] = str_map(req.get("data"), "data")
    out["native"] = str_map(req.get("native"), "native")
    out["user"] = str_map(req.get("user"), "user")
    for k in out["user"]:
        if not k.startswith("quickshell."):
            raise Failure("user keys must start with quickshell.")
    raw = req.get("secrets") or {}
    if not isinstance(raw, dict):
        raise Failure("secrets must be an object")
    secrets = {}
    for k, v in raw.items():
        if not isinstance(v, dict) or v.get("mode") not in ("save", "ask") or not isinstance(v.get("value", ""), str):
            raise Failure("bad secret %s" % k)
        secrets[k] = {"mode": v["mode"], "value": v.get("value", "")}
    out["secrets"] = secrets
    for k in list(out["data"]) + list(secrets):
        if not KEY_RE.match(k):
            raise Failure("bad key %r" % k)
    return out


# ---------- connecting ----------

def nmcli_up(uuid, payload, secrets):
    """nmcli connection up, with payload (passwd-file lines) on a pipe."""
    nmcli = os.environ.get("NM_VPN_NMCLI_BIN", "nmcli")
    wait = int(os.environ.get("NM_VPN_CONNECT_WAIT", "90"))
    args = [nmcli, "--wait", str(wait), "connection", "up", "uuid", uuid]
    if len(payload.encode()) > MAX_PASSWD_BYTES:
        raise Failure("Secrets are too long")
    read_end = None
    fds = ()
    if payload:
        read_end, write_end = os.pipe()
        os.write(write_end, payload.encode())   # fits the pipe buffer, so this never blocks
        os.close(write_end)
        args += ["passwd-file", "/dev/fd/%d" % read_end]
        fds = (read_end,)
    try:
        proc = subprocess.run(args, pass_fds=fds, capture_output=True, text=True, timeout=wait + 15)
    except FileNotFoundError:
        raise Failure("nmcli not found")
    except subprocess.TimeoutExpired:
        raise Failure("Timed out connecting")
    finally:
        if read_end is not None:
            os.close(read_end)
    if proc.returncode != 0:
        msg = nmcli_message(proc.stderr) or nmcli_message(proc.stdout) or "nmcli exited with code %d" % proc.returncode
        raise Failure(scrub(msg, secrets))


# ---------- commands ----------

def service_for(backend, type_name):
    if type_name == WIREGUARD:
        return None
    for t in backend.types():
        if t["name"] == type_name:
            return t["service"]
    raise Failure("VPN type %s is not installed" % type_name)


def cmd_types(backend, req):
    return {"ok": True, "types": backend.types()}


def cmd_get(backend, req):
    return {"ok": True, "profile": describe(backend.load(need_str(req, "uuid")))}


def cmd_add(backend, req):
    r = parse_edit(req, need_uuid=False)
    rec = new_record(r, service_for(backend, r["type"]))
    return {"ok": True, "uuid": backend.create(rec)}


def cmd_update(backend, req):
    r = parse_edit(req, need_uuid=True)
    rec = backend.load(r["uuid"])
    if rec["type"] != r["type"]:
        raise Failure("%s is a %s profile, not %s" % (rec["name"], rec["type"], r["type"]))
    backend.save(apply_request(rec, r))
    return {"ok": True}


def cmd_import(backend, req):
    type_name = need_str(req, "type")
    path = os.path.expanduser(need_str(req, "path"))
    if not os.path.isfile(path):
        raise Failure("No such file: %s" % path)
    return {"ok": True, "uuid": backend.import_file(type_name, path)}


def cmd_connect(backend, req):
    uuid = need_str(req, "uuid")
    given = req.get("secrets") or {}
    if not isinstance(given, dict) or not all(isinstance(v, str) for v in given.values()):
        raise Failure("secrets must map keys to strings")
    rec = backend.load(uuid)
    asked = ask_keys(rec)
    missing = [k for k in asked if k not in given]
    if missing:
        return {"ok": False, "need": missing, "type": rec["type"]}
    wanted = {k: given[k] for k in asked}
    nmcli_up(uuid, passwd_lines(rec, wanted), list(wanted.values()))
    return {"ok": True}


HANDLERS = {"types": cmd_types, "get": cmd_get, "add": cmd_add, "update": cmd_update,
            "import": cmd_import, "connect": cmd_connect}


# ---------- backends ----------

SECRETS_UNREADABLE = "Could not read the profile's saved secrets; nothing was changed. Try again."


class FakeBackend:
    """JSON-file stand-in for libnm (tests only: NM_VPN_FAKE_STATE)."""

    def __init__(self, path):
        self.path = path
        with open(path) as f:
            self.state = json.load(f)
        for k in ("types", "profiles", "imports"):
            self.state.setdefault(k, [] if k == "types" else {})

    def _write(self):
        with open(self.path, "w") as f:
            json.dump(self.state, f, indent=1, sort_keys=True)

    @staticmethod
    def _complete(rec):
        for k in ("data", "secrets", "native", "user"):
            rec.setdefault(k, {})
        rec.setdefault("service", None)
        return rec

    def types(self):
        return list(self.state["types"])

    def load(self, uuid):
        rec = self.state["profiles"].get(uuid)
        if rec is None:
            raise Failure("No VPN profile %s" % uuid)
        rec = self._complete(json.loads(json.dumps(rec)))
        rec["uuid"] = uuid
        return rec

    def _store(self, rec):
        stored = {k: v for k, v in rec.items() if k != "uuid"}
        # Like NetworkManager: only secrets with flags 0 are kept.
        stored["secrets"] = {k: v for k, v in rec["secrets"].items() if get_flags(rec, k) == 0}
        self.state["profiles"][rec["uuid"]] = stored
        self._write()

    def create(self, rec):
        rec["uuid"] = "fake-%d" % (len(self.state["profiles"]) + 1)
        self._store(rec)
        return rec["uuid"]

    def save(self, rec):
        if rec.get("secrets_unreadable"):
            raise Failure(SECRETS_UNREADABLE)
        self._store(rec)

    def import_file(self, type_name, path):
        src = self.state["imports"].get(os.path.basename(path))
        if src is None or src.get("type") != type_name:
            raise Failure("Cannot import %s as %s" % (os.path.basename(path), type_name))
        return self.create(self._complete(json.loads(json.dumps(src))))


class LibnmBackend:
    """NetworkManager through libnm (PyGObject). Every D-Bus call has a 30 s
    timeout. Profiles are edited in place, so settings this helper doesn't
    manage (routes, proxy, permissions, ...) survive an update."""

    def __init__(self):
        try:
            import gi
            gi.require_version("NM", "1.0")
            from gi.repository import GLib, NM
        except (ImportError, ValueError) as e:
            raise Failure("libnm is not available: %s" % e)
        self.GLib, self.NM = GLib, NM
        try:
            self.client = NM.Client.new(None)
        except GLib.Error as e:
            raise Failure("NetworkManager is not reachable: %s" % e.message)
        self._plugins = None

    # --- plumbing ---
    def _call(self, start, finish):
        GLib = self.GLib
        loop = GLib.MainLoop()
        box = {}

        def done(src, res, *_):
            try:
                box["value"] = finish(src, res)
            except GLib.Error as e:
                box["error"] = e.message
            loop.quit()

        def expire():
            box.setdefault("error", "Timed out talking to NetworkManager")
            box["expired"] = True
            loop.quit()
            return False

        start(done)
        timer = GLib.timeout_add_seconds(30, expire)
        loop.run()
        if not box.get("expired"):
            GLib.source_remove(timer)
        if "error" in box:
            raise Failure(box["error"])
        return box.get("value")

    def plugins(self):
        if self._plugins is None:
            NM = self.NM
            out = []
            for info in NM.VpnPluginInfo.list_load():
                editor, can_import = None, False
                try:
                    editor = info.load_editor_plugin()
                    can_import = bool(editor.get_capabilities() & NM.VpnEditorPluginCapability.IMPORT)
                except self.GLib.Error:
                    pass
                out.append({"name": info.get_name(), "service": info.get_service(), "import": can_import, "_editor": editor})
            self._plugins = out
        return self._plugins

    def _type_for_service(self, service):
        for p in self.plugins():
            if p["service"] == service:
                return p["name"]
        return (service or "").rsplit(".", 1)[-1]

    def _remote(self, uuid):
        rc = self.client.get_connection_by_uuid(uuid)
        if rc is None:
            raise Failure("No VPN profile %s" % uuid)
        return rc

    def _add(self, conn):
        added = self._call(lambda cb: self.client.add_connection_async(conn, True, None, cb, None),
                           lambda src, res: src.add_connection_finish(res))
        return added.get_uuid()

    # --- interface ---
    def types(self):
        t = [{k: v for k, v in p.items() if not k.startswith("_")} for p in self.plugins()]
        t.append({"name": WIREGUARD, "service": None, "import": True})
        return t

    def load(self, uuid):
        rc = self._remote(uuid)
        ctype = rc.get_connection_type()
        if ctype == "vpn":
            setting_name = "vpn"
        elif ctype == "wireguard":
            setting_name = "wireguard"
        else:
            raise Failure("%s is not a VPN" % rc.get_id())
        unreadable = False
        try:   # secrets come back only for this caller; none at all is fine
            sec = self._call(lambda cb: rc.get_secrets_async(setting_name, None, cb, None),
                             lambda src, res: src.get_secrets_finish(res))
            if sec is not None:
                rc.update_secrets(setting_name, sec)
        except (Failure, self.GLib.Error):
            unreadable = True   # save() refuses: it would erase the stored secrets
        rec = {"uuid": uuid, "name": rc.get_id(), "service": None,
               "data": {}, "secrets": {}, "native": {}, "user": {},
               "secrets_unreadable": unreadable}
        if ctype == "vpn":
            s = rc.get_setting_vpn()
            rec["service"] = s.get_service_type()
            rec["type"] = self._type_for_service(rec["service"])
            for k in s.get_data_keys() or []:
                rec["data"][k] = s.get_data_item(k)
            for k in s.get_secret_keys() or []:
                rec["secrets"][k] = s.get_secret(k)
        else:
            rec["type"] = WIREGUARD
            self._read_wireguard(rc, rec)
        ip4 = rc.get_setting_ip4_config()
        if ip4 is not None:
            rec["native"]["ipv4.never-default"] = "yes" if ip4.get_never_default() else "no"
        s_user = rc.get_setting_by_name("user")
        if s_user is not None:
            for k in s_user.get_keys() or []:
                rec["user"][k] = s_user.get_data(k)
        return rec

    def _read_wireguard(self, conn, rec):
        n = rec["native"]
        s = conn.get_setting_by_name("wireguard")
        if s.get_private_key():
            rec["secrets"]["wireguard.private-key"] = s.get_private_key()
        n["wireguard.private-key-flags"] = str(int(s.get_private_key_flags()))
        if s.get_listen_port():
            n["wireguard.listen-port"] = str(s.get_listen_port())
        iface = conn.get_setting_connection().get_interface_name()
        if iface:
            n["connection.interface-name"] = iface
        addrs, dns = [], []
        for ip in (conn.get_setting_ip4_config(), conn.get_setting_ip6_config()):
            if ip is None:
                continue
            for i in range(ip.get_num_addresses()):
                a = ip.get_address(i)
                addrs.append("%s/%d" % (a.get_address(), a.get_prefix()))
            for i in range(ip.get_num_dns()):
                dns.append(ip.get_dns(i))
        if addrs:
            n["ipv4.addresses"] = ", ".join(addrs)
        if dns:
            n["ipv4.dns"] = ", ".join(dns)
        count = s.get_peers_len()
        n["peer.count"] = str(count)
        if count >= 1:
            p = s.get_peer(0)
            n["peer.public-key"] = p.get_public_key() or ""
            if p.get_endpoint():
                n["peer.endpoint"] = p.get_endpoint()
            ips = []
            for i in range(p.get_allowed_ips_len()):
                v = p.get_allowed_ip(i)
                ips.append(v[0] if isinstance(v, tuple) else v)
            if ips:
                n["peer.allowed-ips"] = ", ".join(ips)
            if p.get_persistent_keepalive():
                n["peer.persistent-keepalive"] = str(p.get_persistent_keepalive())
            n["peer.preshared-key-flags"] = str(int(p.get_preshared_key_flags()))
            if p.get_preshared_key():
                rec["secrets"]["peer.preshared-key"] = p.get_preshared_key()

    def _ip_settings(self, conn):
        NM = self.NM
        ip4 = conn.get_setting_ip4_config()
        if ip4 is None:
            ip4 = NM.SettingIP4Config.new()
            ip4.set_property("method", "auto")
            conn.add_setting(ip4)
        ip6 = conn.get_setting_ip6_config()
        if ip6 is None:
            ip6 = NM.SettingIP6Config.new()
            ip6.set_property("method", "auto")
            conn.add_setting(ip6)
        return ip4, ip6

    def _write_wireguard(self, conn, rec):
        NM, n = self.NM, rec["native"]
        s = conn.get_setting_by_name("wireguard")
        if s is None:
            s = NM.SettingWireGuard.new()
            conn.add_setting(s)
        s.set_property("private-key", rec["secrets"].get("wireguard.private-key"))
        s.set_property("private-key-flags", int(n.get("wireguard.private-key-flags", "0") or 0))
        s.set_property("listen-port", int(n.get("wireguard.listen-port") or 0))
        ip4, ip6 = self._ip_settings(conn)
        for ip in (ip4, ip6):
            ip.clear_addresses()
            ip.clear_dns()
        try:
            for a in split_list(n.get("ipv4.addresses", "")):
                v6 = ":" in a
                addr, _, prefix = a.partition("/")
                family = socket.AF_INET6 if v6 else socket.AF_INET
                (ip6 if v6 else ip4).add_address(NM.IPAddress.new(family, addr, int(prefix) if prefix else (128 if v6 else 32)))
        except (ValueError, self.GLib.Error) as e:
            raise Failure("Bad address: %s" % getattr(e, "message", e))
        for d in split_list(n.get("ipv4.dns", "")):
            (ip6 if ":" in d else ip4).add_dns(d)
        ip4.set_property("method", "manual" if ip4.get_num_addresses() else "disabled")
        ip6.set_property("method", "manual" if ip6.get_num_addresses() else "disabled")
        if int(n.get("peer.count") or 0) > 1:
            return                                  # several peers: left as imported
        s.clear_peers()
        if not n.get("peer.public-key"):
            return
        p = NM.WireGuardPeer.new()
        if not p.set_public_key(n["peer.public-key"], False):
            raise Failure("The peer public key is not a valid WireGuard key")
        if n.get("peer.endpoint") and not p.set_endpoint(n["peer.endpoint"], False):
            raise Failure("The peer endpoint must look like host:port")
        for ip in split_list(n.get("peer.allowed-ips", "")):
            if not p.append_allowed_ip(ip, False):
                raise Failure("Bad allowed IP %s" % ip)
        if n.get("peer.persistent-keepalive"):
            p.set_persistent_keepalive(int(n["peer.persistent-keepalive"]))
        psk = rec["secrets"].get("peer.preshared-key")
        if psk and not p.set_preshared_key(psk, False):
            raise Failure("The peer pre-shared key is not a valid WireGuard key")
        p.set_preshared_key_flags(int(n.get("peer.preshared-key-flags", "0") or 0))
        p.seal()
        s.append_peer(p)

    def _apply_to(self, conn, rec):
        NM = self.NM
        conn.get_setting_connection().set_property("id", rec["name"])
        if rec["type"] == WIREGUARD:
            self._write_wireguard(conn, rec)
        else:
            s = conn.get_setting_vpn()
            if s is None:
                s = NM.SettingVpn.new()
                conn.add_setting(s)
            s.set_property("service-type", rec["service"])
            for k in list(s.get_data_keys() or []):
                s.remove_data_item(k)
            for k in list(s.get_secret_keys() or []):
                s.remove_secret(k)
            for k, v in rec["data"].items():
                s.add_data_item(k, v)
            for k, v in rec["secrets"].items():
                s.add_secret(k, v)
        ip4, _ = self._ip_settings(conn)
        never = rec["native"].get("ipv4.never-default")
        if never is not None:
            ip4.set_property("never-default", never == "yes")
        if rec["user"]:
            s_user = conn.get_setting_by_name("user")
            if s_user is None:
                s_user = NM.SettingUser.new()
                conn.add_setting(s_user)
            for k, v in rec["user"].items():
                try:
                    s_user.set_data(k, v)
                except self.GLib.Error as e:
                    raise Failure("Bad user key %s: %s" % (k, e.message))

    def create(self, rec):
        NM = self.NM
        conn = NM.SimpleConnection.new()
        s_con = NM.SettingConnection.new()
        s_con.set_property("uuid", NM.utils_uuid_generate())
        s_con.set_property("type", "wireguard" if rec["type"] == WIREGUARD else "vpn")
        s_con.set_property("autoconnect", False)
        if rec["type"] == WIREGUARD:
            s_con.set_property("interface-name", rec["native"].get("connection.interface-name") or wg_ifname(rec["name"]))
        conn.add_setting(s_con)
        self._apply_to(conn, rec)
        return self._add(conn)

    def save(self, rec):
        if rec.get("secrets_unreadable"):
            raise Failure(SECRETS_UNREADABLE)
        rc = self._remote(rec["uuid"])            # load() already merged the secrets into rc
        conn = self.NM.SimpleConnection.new_clone(rc)
        self._apply_to(conn, rec)
        rc.replace_settings_from_connection(conn)
        self._call(lambda cb: rc.commit_changes_async(True, None, cb, None),
                   lambda src, res: src.commit_changes_finish(res))

    def import_file(self, type_name, path):
        NM, GLib = self.NM, self.GLib
        try:
            if type_name == WIREGUARD:
                conn = NM.conn_wireguard_import(path)
            else:
                p = next((p for p in self.plugins() if p["name"] == type_name), None)
                if p is None:
                    raise Failure("VPN type %s is not installed" % type_name)
                if not p["import"]:
                    raise Failure("%s cannot import files" % type_name)
                conn = p["_editor"].import_(path)
        except GLib.Error as e:
            raise Failure(e.message)
        return self._add(conn)


def make_backend():
    fake = os.environ.get("NM_VPN_FAKE_STATE")
    return FakeBackend(fake) if fake else LibnmBackend()


# ---------- main ----------

def emit(result):
    sys.stdout.write(json.dumps(result) + "\n")
    sys.stdout.flush()


def main(argv):
    if len(argv) != 2 or argv[1] not in HANDLERS:
        emit({"ok": False, "error": "usage: nm-vpn <%s>" % "|".join(HANDLERS)})
        return 2
    raw = sys.stdin.read()
    try:
        req = json.loads(raw) if raw.strip() else {}
    except ValueError:
        emit({"ok": False, "error": "request is not JSON"})
        return 0
    if not isinstance(req, dict):
        emit({"ok": False, "error": "request must be a JSON object"})
        return 0
    secrets = request_secrets(req)
    try:
        result = HANDLERS[argv[1]](make_backend(), req)
    except Failure as e:
        result = {"ok": False, "error": scrub(str(e), secrets)}
    except Exception as e:  # never let a traceback (which may echo a request) escape
        result = {"ok": False, "error": scrub("internal error: %s" % e.__class__.__name__, secrets)}
    emit(result)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
