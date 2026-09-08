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
  programs.nushell = {
    enable = true;
    package = pkgs-master.nushell;
  };
}
