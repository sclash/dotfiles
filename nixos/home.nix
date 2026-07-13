{
  config,
  lib,
  pkgs,
  pkgs-unstable,
  neovimrc,
  my-dotfiles,
  ...
}:
# let
#   tpm = pkgs.fetchFromGitHub {
#     owner = "tmux-plugins";
#     repo = "tpm";
#     rev = "master";
#     sha256 = "01ribl326n6n0qcq68a8pllbrz6mgw55kxhf9mjdc5vw01zjcvw5";
#   };
#
# in let
#   my_dotfiles = builtins.fetchGit {
#     url = "https://github.com/sclash/dotfiles";
#     rev = "f095bce2e15e8652eb2b0be28d1417f59ebe19c2";
#     # sha256 = "01ribl326n6n0qcq68a8pllbrz6mgw55kxhf9mjdc5vw01zjcvw5";
#   };
# in
{

  imports = [
    ./programs/tmux/tmux.nix
    ./programs/swaync.nix
    ./programs/zsh.nix
    ./programs/starship.nix
    ./programs/atuin.nix
    ./programs/obs.nix
    ./programs/pandoc.nix
    ./programs/claude-code/claude-code.nix
    ./programs/mcpservers.nix
    ./programs/zathura.nix
    ./programs/opencode/opencode.nix
  ];

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  # home.sessionVariables = {
  #   PATH = "${my-dotfiles}/bin:${config.home.sessionVariables.PATH or ""}";
  # };
  home.sessionPath = [
    "$HOME/.local/bin"
  ];

  # --- Packages ---
  # Install user-specific packages
  home.packages =
    (with pkgs; [
      man-pages
      man-pages-posix
      gh
      eza
      atuin
      ncdu
      tor-browser
      icu
      nodejs
      typescript
      glow
      vlc
      hygg
      flameshot
      flamegraph
      gemini-cli

      impala
      fastfetch
      bluetui
      lazydocker
      lazysql
      lazyssh
      lazycli

      # for Claude-Code
      mcp-nixos
      rust-analyzer
      pyright
      zls
      gopls
      lua-language-server
      typescript-language-server
      vue-language-server
      tailwindcss-language-server
      python313Packages.markitdown
      playwright

    ])
    ++ (with pkgs-unstable; [
      markitdown-mcp
      rtk
      zennotes-desktop
    ]);

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

  home.file = {
    # ".zshrc".source = ~/dotfiles/zshrc/.zshrc;
    # ".config/zellij".source = ~/dotfiles/zellij;
    # ".config/nvim".source = ~/dotfiles/nvim;
    # ".config/nix".source = ~/dotfiles/nix;
    # ".config/nix-darwin".source = ~/dotfiles/nix-darwin;
    # ".config/tmux".source = ~/dotfiles/tmux;
    # ".config/tmux".source = builtins.path {path = "/home/asergi/dotfiles/tmux";};
    # ".config/tmux".source = builtins.path { path = "${my-dotfiles}/tmux"; };
    # ".config/tmux".source = "${my_dotfiles}/tmux";
    # ".config/tmux".source = "${my-dotfiles}/tmux";
    ".config/nvim" = {
      source = "${neovimrc}";
      # source = "/home/asergi/neovimrc";
      executable = false;
      recursive = true;
      force = true;
    };
    # Example: symlink a script from the repo to ~/.local/bin
    # home.file.".local/bin/myscript" = {
    #   source = "${my-scripts}/myscript.sh";
    #   executable = true;
    # };
    # ".config/tmux/plugins" = "${tpm}";
    # ".config/tmux".source ="${config.home.homeDirectory}/dotfiles/tmux/tmux.conf";
    # "/home/asergi/.config/tmux".source ="/home/asergi/dotfiles/tmux/tmux.conf";
    #    ".config/tmux/plugins".source = pkgs.fetchFromGitHub {
    #      owner = "tmux-plugins";
    #      repo = "tpm";
    #      rev = "master";
    # sha256 = "01ribl326n6n0qcq68a8pllbrz6mgw55kxhf9mjdc5vw01zjcvw5";
    #    };

    #    "${config.home.homeDirectory}/.config/tmux/plugins".source = pkgs.fetchFromGitHub {
    #      owner = "tmux-plugins";
    #      repo = "tpm";
    #      rev = "master";
    # sha256 = "01ribl326n6n0qcq68a8pllbrz6mgw55kxhf9mjdc5vw01zjcvw5";
    #    };
    #    ".config/tmux/plugins".source = builtins.fetchFromGitHub {
    #      owner = "tmux-plugins";
    #      repo = "tpm";
    #      rev = "master";
    # sha256 = "01ribl326n6n0qcq68a8pllbrz6mgw55kxhf9mjdc5vw01zjcvw5";
    #    };

    # ".config/ghostty".source = ~/dotfiles/ghostty;
    ".config/starship" = {
      # source = "${my-dotfiles}/starship";
      # source = "/home/asergi/dotfiles/starship";
      # executable = false;
      # force = true;
      # recursive = true;
      source = config.lib.file.mkOutOfStoreSymlink "/home/asergi/dotfiles/starship";
      force = true;
    };
    ".config/atuin" = {
      # source = "${my-dotfiles}/starship";
      source = "/home/asergi/dotfiles/atuin";
      executable = false;
      force = true;
      recursive = true;
      # source = config.lib.file.mkOutOfStoreSymlink "/home/asergi/dotfiles/atuin";
      # force = true;
    };
    ".config/ghostty" = {
      # source = "${my-dotfiles}/ghostty";
      # source = "/home/asergi/dotfiles/ghostty";
      # executable = false;
      # force = true;
      # recursive = true;
      source = config.lib.file.mkOutOfStoreSymlink "/home/asergi/dotfiles/ghostty";
      force = true;
    };
    ".config/hypr" = {
      # source = "${my-dotfiles}/hypr";
      # source = "/home/asergi/dotfiles/hypr";
      # executable = false;
      # force = true;
      # recursive = true;
      source = config.lib.file.mkOutOfStoreSymlink "/home/asergi/dotfiles/hypr";
      force = true;
    };
    ".config/waybar" = {
      # source = "${my-dotfiles}/waybar";
      # source = "/home/asergi/dotfiles/waybar";
      # executable = false;
      # force = true;
      # recursive = true;
      source = config.lib.file.mkOutOfStoreSymlink "/home/asergi/dotfiles/waybar";
      force = true;
    };
    ".config/swaync" = {
      # source = "${my-dotfiles}/swaync";
      source = "/home/asergi/dotfiles/swaync";
      executable = false;
      force = true;
      recursive = true;
      # source = config.lib.file.mkOutOfStoreSymlink "/home/asergi/dotfiles/swaync";
      # force = true;
    };
    # ".config/ghostty".source = "${my-dotfiles}/tmux";
    # ".config/hypr".source = "${my-dotfiles}/hypr";
    # ".config/waybar".source = "${my-dotfiles}/waybar";
  };

  home.activation.removeStaleConfigDirs = lib.hm.dag.entryBefore [ "linkGeneration" ] ''
    for dir in hypr ghostty waybar starship; do
      target="$HOME/.config/$dir"
      if [ -d "$target" ] && [ ! -L "$target" ]; then
        rm -rf "$target"
      fi
    done
  '';

  home.stateVersion = "25.05"; # Did you read the comment?
}
