{
  config,
  lib,
  pkgs,
  ...
}:
{
  home.username = "asergi";
  home.homeDirectory = "/home/asergi";

  # Ubuntu, not NixOS: XDG data dirs, locale archive and terminfo for Nix
  # programs. Nothing here is GUI, so skip the GPU driver integration (it
  # would otherwise ask for a one-time sudo setup).
  targets.genericLinux.enable = true;
  targets.genericLinux.gpu.enable = false;

  # home-manager master on top of nixpkgs 26.05, as on NixOS.
  home.enableNixpkgsReleaseCheck = false;
  programs.home-manager.enable = true;

  home.language.base = "en_US.UTF-8";

  # Native installers live here: claude (~/.local/bin), opencode (~/.opencode/bin).
  home.sessionPath = [
    "$HOME/.local/bin"
    "$HOME/.opencode/bin"
  ];

  # No LD_LIBRARY_PATH: on Ubuntu it would push Nix's libstdc++ into system
  # binaries built against the older glibc.
  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
    SUDO_EDITOR = "nvim";
  };

  programs.git = {
    enable = true;
    settings = {
      user.name = "sclash";
      user.email = "andrea.sergi1@gmail.com";
      github.user = "sclash";
      init.defaultBranch = "main";
      color.ui = true;
    };
  };

  programs.man = {
    enable = true;
  };

  home.stateVersion = "26.05";
}
