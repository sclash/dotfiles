{
  config,
  lib,
  pkgs,
  pkgs-unstable,
  # my-dotfiles,
  ...
}:

{
  programs.herdr = {
    enable = true;
    package = pkgs-unstable.herdr;
  };

  home.file = {
    ".config/herdr" = {
      source = config.lib.file.mkOutOfStoreSymlink "/home/asergi/dotfiles/herdr";
      force = true;
    };
  };
}
