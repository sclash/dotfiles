{
  config,
  lib,
  pkgs,
  ...
}:
let
  user = import ../lib/user.nix;
  dotfiles = user.dotfiles;
  link = config.lib.file.mkOutOfStoreSymlink;
in
{
  # Portable modules shared with the NixOS config, imported unchanged.
  imports = [
    ../nixos/programs/tmux/tmux.nix
    ../nixos/programs/starship.nix
    ../nixos/programs/atuin.nix
    ../nixos/programs/uv/uv.nix
    ../nixos/programs/pandoc.nix
    ../nixos/programs/nushell.nix
    ../nixos/programs/devenv.nix
    ../nixos/programs/nvim-lsp.nix
    ../nixos/programs/ripwire.nix
    ./modules/herdr.nix
    ./modules/secrets.nix
    ./modules/zsh.nix
    ./modules/opencode.nix
    ./modules/claude-code.nix
    ./packages.nix
  ];

  home.username = user.username;
  home.homeDirectory = user.homeDirectory;

  # Linux, not NixOS: XDG data dirs, locale archive and terminfo for Nix
  # programs. Nothing here is GUI, so skip the GPU driver integration (it
  # would otherwise ask for a one-time sudo setup).
  targets.genericLinux.enable = true;
  targets.genericLinux.gpu.enable = false;

  # home-manager master on top of nixpkgs 26.05, as on NixOS.
  home.enableNixpkgsReleaseCheck = false;
  programs.home-manager.enable = true;

  # Build limits for the small WSL VM (3.6 GiB): one derivation at a time and
  # two compile threads, so an uncached C++/Rust build can't exhaust memory.
  # nix.package only validates the generated nix.conf and is not installed,
  # so Determinate's nix stays the one on PATH.
  nix.package = pkgs.nix;
  nix.settings = {
    max-jobs = 1;
    cores = 2;
  };

  home.language.base = "en_US.UTF-8";

  # Claude Code and opencode come from pkgs-unstable; ~/.local/bin is kept for
  # other native tools.
  home.sessionPath = [
    "$HOME/.local/bin"
  ];

  # No LD_LIBRARY_PATH: on Linux it would push Nix's libstdc++ into system
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
      # `less` is not installed; without this, paged commands (git log/diff/show)
      # fail with "unable to execute pager 'less'". bat keeps syntax colours.
      core.pager = "bat --plain";
    };
  };

  programs.man = {
    enable = true;
  };

  home.file = {
    ".config/nvim".source = link "${dotfiles}/neovimrc";
    ".config/starship".source = link "${dotfiles}/starship";
    # ".config/atuin".source = link "${dotfiles}/atuin";
    # WSL copy: python-preference = "managed", so uv's standalone Pythons load
    # PyPI wheels against the distro's libstdc++ without any LD_LIBRARY_PATH.
    ".config/uv/uv.toml".source = lib.mkForce (link "${dotfiles}/wsl/uv/uv.toml");
  };

  home.stateVersion = "26.05";
}
