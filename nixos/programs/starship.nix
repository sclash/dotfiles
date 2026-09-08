{
  config,
  lib,
  pkgs,
  unstable-pkgs,
  # my-dotfiles,
  ...
}:

{
  programs.starship = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
    enableNuIntegration = true;
    enableTransience = true;
    configPath = "${config.xdg.configHome}/starship/starship.toml";
  };
}
