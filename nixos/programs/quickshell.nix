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

  home.file = {
    ".config/quickshell" = {
      source = config.lib.file.mkOutOfStoreSymlink "/home/asergi/dotfiles/quickshell";
      force = true;
    };
  };
}
