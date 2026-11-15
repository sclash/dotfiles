{
  config,
  inputs,
  ...
}:

{
  # Rex ships its own home-manager module in the same flake as its package:
  # programs.rex installs the binary, the xterm-rex terminfo entry and the ssh
  # guard; services.rex runs the personal server as a systemd user service.
  # Without linger, that service starts on login (SSH included) and stops on
  # logout, saving the sessions for the next start to restore.
  imports = [ inputs.rex.homeManagerModules.default ];

  programs.rex.enable = true;
  services.rex.enable = true;

  # The guard needs programs.ssh, and enableDefaultConfig = false keeps
  # ~/.ssh/config to the Include line instead of home-manager's defaults.
  programs.ssh.enable = true;
  programs.ssh.enableDefaultConfig = false;

  # Mirror programs/herdr.nix: live config from the dotfiles checkout. Do not
  # also set programs.rex.config, which would write through this symlink.
  home.file.".config/rex".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/rex";
}
