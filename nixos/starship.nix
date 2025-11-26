{ config, lib, pkgs, unstable-pkgs, my-dotfiles, ... }:

{

  programs.starship = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
    enableTransience = true;
    # presets = builtins.readFile "${my-dotfiles}/starship/starship.toml";
    presets =  [ "${my-dotfiles}/starship/starship.toml" ];
  };
}
