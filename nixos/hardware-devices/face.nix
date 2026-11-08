# Face unlock (Howdy over an IR camera) for the lock screen only.
#
# Howdy is installed everywhere; on machines without an IR camera it never
# runs. Its PAM module is limited to one dedicated service, `hyprlock-face`
# (Howdy `sufficient`, then the usual password check). hyprlock picks that
# service through `auth:pam:module`, which the Quickshell Identity Manager
# (SUPER+I) writes per user in ~/.local/state/hyprlock-auth.conf, so face
# unlock is switched on and off without root or a rebuild. hyprlock starts
# PAM when Enter is pressed: Enter on an empty field = "look at the camera".
#
# Face models are per machine and per user (/var/lib/howdy/models), never in
# this repo. Howdy can be fooled by a good photo, which is why it is never
# allowed for sudo, su, polkit, ssh or login.
{ config, lib, ... }:

let
  faceService = "hyprlock-face";

  # Laptop IR (Windows Hello) cameras expose a second UVC interface whose
  # name says so (e.g. "HP IR Camera", "Integrated IR Camera"). Index 0 is the
  # picture stream; the other node of the pair carries metadata. A camera
  # with an unusual name can be pointed at from /etc/nixos/machine.nix with
  # `services.howdy.settings.video.device_path`.
  irCamera = "/dev/v4l/ir0";
in
{
  services.howdy = {
    enable = true;
    # Between mkDefault (the module's own default) and a plain assignment,
    # so a machine.nix override wins without lib.mkForce.
    settings.video.device_path = lib.mkOverride 900 irCamera;
  };

  services.udev.extraRules = ''
    SUBSYSTEM=="video4linux", KERNEL=="video[0-9]*", ATTR{index}=="0", ATTR{name}=="*IR Camera*|*IR camera*|*Infrared*", SYMLINK+="v4l/ir0", TAG+="systemd"
  '';

  # Some IR emitters stay dark until switched on with a per-machine setting
  # found by `sudo linux-enable-ir-emitter configure` (saved in
  # /var/lib/linux-enable-ir-emitter). Until that has run, or without an IR
  # camera, the unit is skipped instead of failing.
  services.linux-enable-ir-emitter = {
    enable = true;
    device = "v4l-ir0"; # systemd's name for /dev/v4l/ir0
  };
  systemd.services.linux-enable-ir-emitter.unitConfig = {
    ConditionPathExists = irCamera;
    ConditionDirectoryNotEmpty = "/var/lib/linux-enable-ir-emitter";
  };

  # Howdy's PAM module would otherwise be added to every service as
  # `required`. Off everywhere, on only for the lock screen's face service.
  security.pam.howdy.enable = false;
  security.pam.services.${faceService}.howdy = {
    enable = true;
    control = "sufficient";
  };

  assertions = [
    {
      assertion = lib.all (
        n: n == faceService || !(config.security.pam.services.${n}.enable && config.security.pam.services.${n}.howdy.enable)
      ) (lib.attrNames config.security.pam.services);
      message = ''
        face: a PAM service other than ${faceService} enables Howdy.
        Face unlock is lock-screen only; see nixos/hardware-devices/face.nix.
      '';
    }
  ];
}
