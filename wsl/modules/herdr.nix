{
  config,
  pkgs-master,
  ...
}:
{
  programs.herdr = {
    enable = true;
    package = pkgs-master.herdr;
  };

  # Only config.toml: herdr keeps its sockets, logs and session.json in
  # ~/.config/herdr, which must not end up in the repo. With empty settings
  # the herdr module leaves config.toml unmanaged, so this link owns it.
  xdg.configFile."herdr/config.toml".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/herdr/config.toml";
}
