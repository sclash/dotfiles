#!/usr/bin/env bash
# Asserts the fingerprint/PAM scoping of nixos/hardware-devices/fingerprint.nix:
# fprintd is enabled, but no PAM service uses pam_fprintd; enabling it on any
# service fails evaluation (assertion). hyprlock uses the native fprintd
# integration instead (see hypr/hyprlock.conf, checked in Task 3).
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
STUB_DIR=$(mktemp -d)
trap 'rm -rf "$STUB_DIR"' EXIT
cp "$ROOT/nixos/tests/stub-machine.nix" "$STUB_DIR/hardware-configuration.nix"
printf '{ }\n' > "$STUB_DIR/machine.nix"

cat > "$STUB_DIR/check.nix" <<'NIX'
let
  root = builtins.getEnv "FPRINT_CHECK_ROOT";
  f = builtins.getFlake ("git+file://" + root + "?dir=nixos");
  c = f.nixosConfigurations.default;
  lib = f.inputs.nixpkgs.lib;
  svcs = c.config.security.pam.services;
  names = builtins.attrNames svcs;
  enabled = builtins.filter (n: svcs.${n}.enable && svcs.${n}.fprintAuth) names;
  texts = builtins.map (n: svcs.${n}.text) names;
  usesFprintd = builtins.filter (t: lib.hasInfix "pam_fprintd" t) texts;
  # Assertions are enforced on the production path: system.build.toplevel
  # evaluates only when every assertion holds. (Scanning config.assertions
  # directly is unreliable: foreign assertion messages can be broken thunks
  # on stub machines and are only forced for failed assertions anyway.)
  ext = (c.extendModules { modules = [ { security.pam.services.sudo.fprintAuth = lib.mkForce true; } ]; }).config;
  baseBuild = builtins.tryEval c.config.system.build.toplevel.drvPath;
  violationBuild = builtins.tryEval ext.system.build.toplevel.drvPath;
  violationEnabled = builtins.filter
    (n: ext.security.pam.services.${n}.enable && ext.security.pam.services.${n}.fprintAuth)
    (builtins.attrNames ext.security.pam.services);
in
{
  fprintdEnabled = c.config.services.fprintd.enable;
  enabledCount = builtins.length enabled;
  fprintdCount = builtins.length usesFprintd;
  baseBuilds = baseBuild.success;
  violationFails = !violationBuild.success;
  violationEnabledCount = builtins.length violationEnabled;
}
NIX

result=$(FPRINT_CHECK_ROOT="$ROOT" DOTFILES_MACHINE_DIR="$STUB_DIR" \
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

expect '.fprintdEnabled'             "fprintd is enabled"
expect '.enabledCount == 0'          "no PAM service has fprintAuth enabled"
expect '.fprintdCount == 0'          "no PAM text contains pam_fprintd"
expect '.baseBuilds'                 "the base system evaluates (assertions hold)"
expect '.violationFails'             "enabling fprintAuth on sudo fails evaluation"
expect '.violationEnabledCount >= 1' "the violation flips a PAM service"

# hyprlock.conf: fingerprint enabled and password-only PAM by default (the
# Identity Manager's generated override narrows both), override source last.
last_line=$(grep -v '^[[:space:]]*$' "$ROOT/hypr/hyprlock.conf" | tail -n 1)
if [[ "$last_line" == "source = ~/.local/state/hyprlock-auth.conf" ]]; then
  echo "OK   hyprlock.conf ends with the state-file source line"
else
  echo "FAIL hyprlock.conf source line is not last (got: $last_line)"
  failures=$((failures + 1))
fi
auth_block=$(sed -n '/^auth {/,/^}/p' "$ROOT/hypr/hyprlock.conf")
if grep -q 'enabled = true' <<<"$auth_block"; then
  echo "OK   hyprlock.conf enables fingerprint by default"
else
  echo "FAIL hyprlock.conf does not enable fingerprint"
  failures=$((failures + 1))
fi
if grep -qE 'module = hyprlock$' <<<"$auth_block"; then
  echo "OK   hyprlock.conf uses the password-only PAM service by default"
else
  echo "FAIL hyprlock.conf default PAM module is not hyprlock"
  failures=$((failures + 1))
fi

if ((failures)); then
  echo "$failures fingerprint tests failed"
  exit 1
fi
echo "OK (fingerprint tests)"
