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
  ] ++ (with pkgs-unstable; [
    # elephant or walker backend for AppLauncher — whichever is packaged
  ]);

  home.file = {
    ".config/quickshell" = {
      source = config.lib.file.mkOutOfStoreSymlink "/home/asergi/dotfiles/quickshell";
      force = true;
    };
  };
}
