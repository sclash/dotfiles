#!/usr/bin/env bash
# Asserts the VPN wiring of the evaluated config: the NetworkManager VPN
# plugins the Network Center offers (/vpn), the nm-vpn helper in the user's
# packages, services.strongswan kept for L2TP/IPsec, and /etc/strongswan.conf.
# Run: bash nixos/tests/test-vpn.sh
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
STUB_DIR=$(mktemp -d)
trap 'rm -rf "$STUB_DIR"' EXIT
cp "$ROOT/nixos/tests/stub-machine.nix" "$STUB_DIR/hardware-configuration.nix"
printf '{ }\n' > "$STUB_DIR/machine.nix"

cat > "$STUB_DIR/check.nix" <<'NIX'
let
  root = builtins.getEnv "VPN_CHECK_ROOT";
  f = builtins.getFlake ("git+file://" + root + "?dir=nixos");
  c = f.nixosConfigurations.default.config;
  user = builtins.head (builtins.attrNames c.home-manager.users);
  names = ps: map (p: p.pname or p.name) ps;
in
{
  plugins = names c.networking.networkmanager.plugins;
  home = names c.home-manager.users.${user}.home.packages;
  strongswan = c.services.strongswan.enable;
  strongswanConf = c.environment.etc ? "strongswan.conf";
  systemEvaluates = (builtins.tryEval c.system.build.toplevel.drvPath).success;
}
NIX

result=$(VPN_CHECK_ROOT="$ROOT" DOTFILES_MACHINE_DIR="$STUB_DIR" \
  nix eval --impure --json --file "$STUB_DIR/check.nix")

failures=0
expect() { # jq-filter, description
  if [[ $(printf '%s' "$result" | jq -r "$1") == "true" ]]; then
    echo "OK   $2"
  else
    echo "FAIL $2 (result: $result)"
    failures=$((failures + 1))
  fi
}

expect '[.plugins[] | test("openvpn")] | any'    "the OpenVPN plugin is installed"
expect '[.plugins[] | test("l2tp")] | any'       "the L2TP plugin is installed"
expect '[.plugins[] | test("strongswan")] | any' "the strongSwan (IKEv2) plugin is installed"
expect '.home | index("nm-vpn") != null'         "nm-vpn is in the user's packages"
expect '.strongswan'                             "services.strongswan stays enabled (L2TP/IPsec)"
expect '[.home[] | test("network-manager-applet")] | any | not' "networkmanagerapplet is gone (no nm-connection-editor, no nm-applet)"
expect '.strongswanConf'                         "/etc/strongswan.conf exists (charon-nm aborts without it)"
expect '.systemEvaluates'                        "the full NixOS system evaluates (no insecure or broken packages)"

if ((failures)); then echo "$failures VPN config checks failed"; exit 1; fi
echo "OK (VPN config checks)"
