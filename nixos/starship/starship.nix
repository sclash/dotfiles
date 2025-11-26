{ config, lib, pkgs, unstable-pkgs, my-dotfiles, ... }:

{

  programs.starship = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
    enableTransience = true;
    settings = builtins.readFile "${my-dotfiles}/nixos/starship/starship.toml";
  };
}
