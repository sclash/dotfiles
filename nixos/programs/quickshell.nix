{
  config,
  lib,
  pkgs,
  pkgs-unstable,
  # my-dotfiles,
  ...
}:

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
  ] ++ (with pkgs-unstable; [
    # elephant or walker backend for AppLauncher — whichever is packaged
  ]);

  home.file = {
    ".config/quickshell" = {
      source = config.lib.file.mkOutOfStoreSymlink "/home/asergi/dotfiles/quickshell";
      force = true;
    };
    # Walker (AppLauncher backend) — config.toml + themes/, raw files in
    # quickshell/walker-style/. Out-of-store: CSS edits only need a walker restart.
    ".config/walker" = {
      source = config.lib.file.mkOutOfStoreSymlink "/home/asergi/dotfiles/quickshell/walker-style";
      force = true;
    };
    # GTK4 global settings — block caret, no blink (walker search parity).
    # Raw file in quickshell/gtk4/settings.ini.
    # ".config/gtk-4.0" = {
    #   source = config.lib.file.mkOutOfStoreSymlink "/home/asergi/dotfiles/quickshell/gtk4";
    #   force = true;
    # };
  };
}
