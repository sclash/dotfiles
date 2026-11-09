{
  config,
  lib,
  pkgs,
  pkgs-unstable,
  # my-dotfiles,
  ...
}:

let
  # GND 0.99.0 hardcodes /usr/libexec/gnome-network-displays-stream for the
  # transient unit it spawns. NixOS has no /usr/libexec, so point it at the
  # package's (wrapped) libexec binary. The stream wrapper also carries the
  # GStreamer/GIO environment that a bare transient unit would otherwise miss.
  gnome-network-displays = pkgs.gnome-network-displays.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      substituteInPlace src/nd-systemd-helpers.c \
        --replace-fail "/usr/libexec/gnome-network-displays-stream" \
          "$out/libexec/gnome-network-displays-stream"
    '';
  });

  # Password changes for the Identity Manager (IdentityService.qml): drives
  # passwd(1) on a pty, passwords on stdin only. Tested by
  # quickshell/tests/test-identity-passwd.sh.
  identity-passwd = pkgs.writers.writePython3Bin "identity-passwd" {
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ../../quickshell/scripts/identity-passwd.py);

  # VPN profiles for the Network Center (NetworkService.qml): libnm through
  # PyGObject, secrets on stdin only. Tested by quickshell/tests/test-nm-vpn.sh
  # and nixos/tests/test-vpn-vm.sh.
  nm-vpn = import ../../quickshell/scripts/nm-vpn.nix { inherit pkgs; };
in
{
  programs.quickshell = {
    enable = true;
    package = pkgs-unstable.quickshell;
    systemd = {
      enable = true;
    };
    # systemd.target = "hyprland-session.target";
    activeConfig = null;
  };

  # On-demand user service used by ScreenCastService (SUPER+SHIFT+K). Deliberately
  # not WantedBy: the launcher starts it only while scanning for cast targets,
  # so machines that never cast do not run Wi-Fi P2P discovery continuously.
  systemd.user.services.gnome-network-displays-daemon = {
    Unit.Description = "GNOME Network Displays daemon";
    Service = {
      # The daemon acquires org.gnome.NetworkDisplays.Manager from its GApplication
      # startup. With the default Type=simple, `systemctl start` returns as soon as
      # the process forks — before the name exists — so the first `busctl
      # get-property` races and fails with "The name is not activatable".
      # Type=dbus blocks `start` until the name is owned.
      Type = "dbus";
      BusName = "org.gnome.NetworkDisplays.Manager";
      ExecStart = "${gnome-network-displays}/bin/gnome-network-displays-daemon";
      Restart = "on-failure";
      RestartSec = 2;
      # A stuck daemon should fail fast instead of holding `start` for 90 s.
      TimeoutStartSec = "15s";
    };
  };

  # Runtime deps for Quickshell services (SPECS.md:2.2)
  home.packages = with pkgs; [
    networkmanager      # nmcli for NetworkService
    wireplumber         # wpctl for AudioService
    pipewire            # pipewire core
    bluez               # bluetoothctl for BluetoothService
    bluez-tools
    lm_sensors          # temp sensors for PerfService
    sysstat
    upower
    udisks2             # udisksctl for UsbService (USB-Manager)
    usbutils            # lsusb for UsbService
    brightnessctl      # internal panel backlight via logind
    ddcutil            # external monitor brightness (VCP 0x10)
    wl-gammarelay-rs   # per-output gamma brightness and color temperature
    gnome-network-displays # Miracast/Chromecast daemon for ScreenCastService
    identity-passwd    # password changes for IdentityService (Identity Manager)
    nm-vpn             # VPN add/import/edit/connect for NetworkService (Network Center)
  ] ++ (with pkgs-unstable; [
    # elephant or walker backend for AppLauncher — whichever is packaged
  ]);

  home.file = {
    ".config/quickshell" = {
      source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/quickshell";
      force = true;
    };
    # Walker (AppLauncher backend) — config.toml + themes/, raw files in
    # quickshell/walker-style/. Out-of-store: CSS edits only need a walker restart.
    ".config/walker" = {
      source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/quickshell/walker-style";
      force = true;
    };
    # GTK4 global settings — block caret, no blink (walker search parity).
    # Raw file in quickshell/gtk4/settings.ini.
    # ".config/gtk-4.0" = {
    #   source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/quickshell/gtk4";
    #   force = true;
    # };
  };
}
