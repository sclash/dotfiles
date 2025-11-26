{ config, lib, pkgs, unstable-pkgs, my-dotfiles, ... }:

{

  programs.starship = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
    enableTransience = true;
    configPath = "${config.xdg.configHome}/starship/starship.toml";
    # configPath = "$XDG_CONFIG_HOME/starship/starship.toml";

    # presets = builtins.readFile "${my-dotfiles}/starship/starship.toml";
    # presets =  [ "${my-dotfiles}/starship/starship.toml" ];
  };
}
