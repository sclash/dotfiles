{
  config,
  lib,
  pkgs,
  pkgs-unstable,
  # my-dotfiles,
  ...
}:

{

  programs.gh = {
    enable = true;
    package = pkgs.atuin;
    settings = {
    	git_protocol = "ssh";
    };
    # configPath = "${config.xdg.configHome}/starship/starship.toml";
  };
}
