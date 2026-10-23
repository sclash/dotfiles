{
  config,
  lib,
  pkgs,
  pkgs-unstable,
  # my-dotfiles,
  ...
}:

{

  programs.atuin = {
    enable = true;
    package = pkgs-unstable.atuin;
    enableBashIntegration = true;
    enableZshIntegration = true;
    enableNushellIntegration = true;
    # configPath = "${config.xdg.configHome}/starship/starship.toml";
  };
}
