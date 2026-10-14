{
  config,
  lib,
  pkgs,
  pkgs-unstable,
  pkgs-master,
  # my-dotfiles,
  ...
}:

{
  programs.herdr = {
    enable = true;
    package = pkgs-master.herdr;
  };

  home.file = {
    ".config/herdr" = {
      source = config.lib.file.mkOutOfStoreSymlink "/home/asergi/dotfiles/herdr";
      force = true;
    };
  };
}
