#!/usr/bin/env bash
# Asserts the face-unlock scoping of nixos/hardware-devices/face.nix:
# Howdy is installed, but only the dedicated `hyprlock-face` PAM service uses
# pam_howdy (as `sufficient`, before pam_unix, so the password always works);
# enabling it on any other service fails evaluation (assertion). The IR camera
# is found by a udev rule, never by a device path that suits one machine.
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
STUB_DIR=$(mktemp -d)
trap 'rm -rf "$STUB_DIR"' EXIT
cp "$ROOT/nixos/tests/stub-machine.nix" "$STUB_DIR/hardware-configuration.nix"
printf '{ }\n' > "$STUB_DIR/machine.nix"

cat > "$STUB_DIR/check.nix" <<'NIX'
let
  root = builtins.getEnv "FACE_CHECK_ROOT";
  f = builtins.getFlake ("git+file://" + root + "?dir=nixos");
  c = f.nixosConfigurations.default;
  lib = f.inputs.nixpkgs.lib;
  svcs = c.config.security.pam.services;
  names = builtins.attrNames svcs;
  howdyOn = builtins.filter (n: svcs.${n}.enable && svcs.${n}.howdy.enable) names;
  usesHowdy = builtins.filter (n: lib.hasInfix "pam_howdy" svcs.${n}.text) names;
  faceText = svcs.hyprlock-face.text;
  authLines = builtins.filter (l: lib.hasPrefix "auth " l) (lib.splitString "\n" faceText);
  idx = pred: let m = lib.lists.findFirstIndex pred null authLines; in if m == null then -1 else m;
  howdyIdx = idx (l: lib.hasInfix "pam_howdy" l);
  unixIdx = idx (l: lib.hasInfix "pam_unix" l);
  howdyLine = if howdyIdx < 0 then "" else builtins.elemAt authLines howdyIdx;
  emitter = c.config.systemd.services.linux-enable-ir-emitter;
  ext = (c.extendModules { modules = [ { security.pam.services.sudo.howdy.enable = lib.mkForce true; } ]; }).config;
  baseBuild = builtins.tryEval c.config.system.build.toplevel.drvPath;
  violationBuild = builtins.tryEval ext.system.build.toplevel.drvPath;
  overridden = (c.extendModules { modules = [ { services.howdy.settings.video.device_path = "/dev/video9"; } ]; }).config;
in
{
  howdyEnabled = c.config.services.howdy.enable;
  howdyServices = howdyOn;
  howdyTexts = usesHowdy;
  faceServiceEnabled = svcs.hyprlock-face.enable;
  faceUsesFprintd = lib.hasInfix "pam_fprintd" faceText;
  howdySufficient = lib.hasInfix "sufficient" howdyLine;
  unixBeforeHowdy = unixIdx >= 0 && howdyIdx > unixIdx;
  plainHyprlockHasHowdy = lib.hasInfix "pam_howdy" svcs.hyprlock.text;
  devicePath = c.config.services.howdy.settings.video.device_path;
  devicePathOverridable = overridden.services.howdy.settings.video.device_path == "/dev/video9";
  udevRule = lib.hasInfix ''SYMLINK+="v4l/ir0"'' c.config.services.udev.extraRules;
  emitterEnabled = c.config.services.linux-enable-ir-emitter.enable;
  emitterNeedsConfig = (emitter.unitConfig.ConditionDirectoryNotEmpty or "") == "/var/lib/linux-enable-ir-emitter";
  emitterNeedsCamera = (emitter.unitConfig.ConditionPathExists or "") == "/dev/v4l/ir0";
  baseBuilds = baseBuild.success;
  violationFails = !violationBuild.success;
}
NIX

result=$(FACE_CHECK_ROOT="$ROOT" DOTFILES_MACHINE_DIR="$STUB_DIR" \
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

expect '.howdyEnabled'                         "Howdy is installed"
expect '.howdyServices == ["hyprlock-face"]'   "only hyprlock-face enables pam_howdy"
expect '.howdyTexts == ["hyprlock-face"]'      "only hyprlock-face's PAM text contains pam_howdy"
expect '.faceServiceEnabled'                   "the hyprlock-face PAM service exists"
expect '.faceUsesFprintd == false'             "hyprlock-face does not use pam_fprintd"
expect '.howdySufficient'                      "pam_howdy is sufficient (password stays a fallback)"
expect '.unixBeforeHowdy'                      "a typed password is checked first; empty Enter falls through to pam_howdy"
expect '.plainHyprlockHasHowdy == false'       "the plain hyprlock service stays password-only"
expect '.devicePath == "/dev/v4l/ir0"'         "Howdy reads the udev-detected IR camera"
expect '.devicePathOverridable'                "machine.nix can override the camera path"
expect '.udevRule'                             "a udev rule creates /dev/v4l/ir0"
expect '.emitterEnabled'                       "the IR emitter service is installed"
expect '.emitterNeedsConfig'                   "the emitter unit skips itself until configured"
expect '.emitterNeedsCamera'                   "the emitter unit skips itself without an IR camera"
expect '.baseBuilds'                           "the base system evaluates (assertions hold)"
expect '.violationFails'                       "enabling Howdy on sudo fails evaluation"

if ((failures)); then
  echo "$failures face tests failed"
  exit 1
fi
echo "OK (face tests)"
