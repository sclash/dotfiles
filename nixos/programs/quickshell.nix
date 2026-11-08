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

  # On-demand user service used by ScreenCastService (SUPER+K). Deliberately
  # not WantedBy: the launcher starts it only while scanning for cast targets,
  # so machines that never cast do not run Wi-Fi P2P discovery continuously.
  systemd.user.services.gnome-network-displays-daemon = {
    Unit.Description = "GNOME Network Displays daemon";
    Service = {
      ExecStart = "${gnome-network-displays}/bin/gnome-network-displays-daemon";
      Restart = "on-failure";
      RestartSec = 2;
    };
  };

  # Runtime deps for Quickshell services (SPECS.md:2.2)
  home.packages = with pkgs; [
    networkmanager      # nmcli for NetworkService
    networkmanagerapplet # nm-connection-editor GUI for NetworkCenter
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
