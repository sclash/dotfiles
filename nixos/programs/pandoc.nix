{ config, lib, pkgs, unstable-pkgs, my-dotfiles, ... }:

{

  programs.pandoc = {
    enable = true;
  };
}
