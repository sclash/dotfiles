{ config, pkgs, pkgs-unstable, my-dotfiles, neovimrc, ... }:
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

  imports = [ ./tmux.nix ./swaync.nix ];

  # home.sessionVariables = {
  #   PATH = "${my-dotfiles}/bin:${config.home.sessionVariables.PATH or ""}";
  # };

  # --- Packages ---
  # Install user-specific packages
  home.packages = (with pkgs; [ eza ]) ++ (with pkgs-unstable; [ ]);

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
    ".config/ghostty" = {
      source = "${my-dotfiles}/ghostty";
      executable = false;
      force = true;
      recursive = true;
    };
    ".config/hypr" = {
      # source = "${my-dotfiles}/hypr";
      source = "/home/asergi/dotfiles/hypr";
      executable = false;
      force = true;
      recursive = true;
    };
    ".config/waybar" = {
      source = "${my-dotfiles}/waybar";
      executable = false;
      force = true;
      recursive = true;
    };
    # ".config/swaync" = {
    #   source = "${my-dotfiles}/swaync";
    #   executable = false;
    #   force = true;
    #   recursive = true;
    # };
    # ".config/ghostty".source = "${my-dotfiles}/tmux";
    # ".config/hypr".source = "${my-dotfiles}/hypr";
    # ".config/waybar".source = "${my-dotfiles}/waybar";
  };

  home.stateVersion = "25.05"; # Did you read the comment?
}
