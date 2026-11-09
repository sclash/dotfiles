#!/usr/bin/env bash
# Runs nixos/tests/vpn-vm.nix: a NixOS VM with NetworkManager, the repo's VPN
# plugins and nm-vpn (spec §14). Needs KVM and takes a few minutes; not part
# of `nix flake check`. Lines starting "VM FINDING" answer the open questions.
# Run: bash nixos/tests/test-vpn-vm.sh
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
if [[ ! -e /dev/kvm ]]; then echo "SKIP no /dev/kvm"; exit 0; fi
STUB_DIR=$(mktemp -d)
trap 'rm -rf "$STUB_DIR"' EXIT
cp "$ROOT/nixos/tests/stub-machine.nix" "$STUB_DIR/hardware-configuration.nix"
printf '{ }\n' > "$STUB_DIR/machine.nix"
cat > "$STUB_DIR/vm.nix" <<'NIX'
let
  root = builtins.getEnv "VPN_VM_ROOT";
  f = builtins.getFlake ("git+file://" + root + "?dir=nixos");
  c = f.nixosConfigurations.default.config;
  pkgs = f.inputs.nixpkgs.legacyPackages.${builtins.currentSystem};
in
import (root + "/nixos/tests/vpn-vm.nix") {
  inherit pkgs;
  plugins = c.networking.networkmanager.plugins;
  strongswanConf = c.environment.etc."strongswan.conf".text;
}
NIX
if VPN_VM_ROOT="$ROOT" DOTFILES_MACHINE_DIR="$STUB_DIR" \
   nix build --impure --no-link -L --file "$STUB_DIR/vm.nix" 2>&1 | tee "$STUB_DIR/log"; then
  grep -o 'VM FINDING.*' "$STUB_DIR/log" || true
  echo "OK (nm-vpn VM test)"
else
  grep -o 'VM FINDING.*' "$STUB_DIR/log" || true
  echo "FAIL nm-vpn VM test"
  exit 1
fi
