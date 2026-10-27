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
    settings = {
	keymap_mode = "vim-normal";
    };
    # configPath = "${config.xdg.configHome}/starship/starship.toml";
  };
}
