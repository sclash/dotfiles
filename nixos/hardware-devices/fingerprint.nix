# Fingerprint reader support and authentication semantics.
#
# Enables the fprintd daemon everywhere (idle on machines without a reader)
# and disables fprintd's PAM integration on every service. Fingerprint unlock
# is hyprlock's native fprintd integration (see hypr/hyprlock.conf, sourced
# from a per-user state file toggled by the Quickshell Identity Manager,
# SUPER+I). Enrollment happens per machine at runtime via the Identity
# Manager or fprintd-enroll; biometric templates live in /var/lib/fprint and
# are never in this repo.
{ config, lib, ... }:

let
  # fprintd's PAM module defaults to enabled on every service when the daemon
  # is on. Keeping it would add fingerprint prompts to sudo/su/sshd/polkit
  # (unattended approvals, CVE-2024-37408, plus pam_fprintd's 30 s fallback
  # delay). The assertion below fails the build if a nixpkgs update adds a
  # fingerprint-enabled service missing from this list.
  passwordOnly = [
    "chfn" "chpasswd" "chsh" "cups" "greetd"
    "groupadd" "groupdel" "groupmems" "groupmod"
    "hyprlock" "i3lock" "i3lock-color" "login" "other" "passwd" "polkit-1"
    "runuser" "runuser-l" "sshd" "su" "sudo"
    "swaylock" "systemd-run0" "systemd-user"
    "useradd" "userdel" "usermod"
    "vlock" "xlock" "xscreensaver"
  ];
in
{
  services.fprintd.enable = true;

  security.pam.services = lib.genAttrs passwordOnly (_: { fprintAuth = false; });

  assertions = [
    {
      assertion = lib.all (
        n: !(config.security.pam.services.${n}.enable && config.security.pam.services.${n}.fprintAuth)
      ) (lib.attrNames config.security.pam.services);
      message = ''
        fingerprint: a PAM service outside the password-only list enables fprintAuth.
        Update nixos/hardware-devices/fingerprint.nix (see its comments).
      '';
    }
  ];
}
