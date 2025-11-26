{ config, lib, pkgs, unstable-pkgs, my-dotfiles, ... }:

{

  programs.starship = {
    enable = true;
    enableBashIntegrasion = true;
    enableZshIntegrasion = true;
    enableTranscience = true;
    settings = builtins.readFile "${my-dotfiles}/nixos/starship/starship.toml";
  };
}
