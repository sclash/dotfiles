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
  programs.devenv = {
    enable = true;
    package = pkgs-master.herdr;
  };
}
