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
  home.packages = [ pkgs-master.ripwire ];

  # home.file = {
  #   ".config/herdr" = {
  #     force = true;
  #   };
  # };
}
