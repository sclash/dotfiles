{ config, lib, pkgs, unstable-pkgs, my-dotfiles, ... }:

{

  programs.atuin = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
    # configPath = "${config.xdg.configHome}/starship/starship.toml";
  };
}
