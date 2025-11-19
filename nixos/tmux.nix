{ config, lib, pkgs, unstable-pkgs, my-dotfiles, ... }:

{

  programs.tmux = {
    enable = true;
    terminal = "tmux-256color";
    keyMode = "vi";

    plugins = with pkgs.tmuxPlugins; [
      sensible
      continuum
      resurrect
      rose-pine
      tmux-sessionx
      # tokyo-night-tmux
    ];
    # extraConfig = builtins.readFile /home/asergi/dotfiles/tmux/tmux.conf;
    # extraConfig = builtins.readFile "/home/asergi/dotfiles/tmux/tmux-nix.conf";
    # extraConfig = builtins.readFile "${my-dotfiles}/tmux/tmux-nix.conf";
    extraConfig = builtins.readFile
      "${config.home.homeDirectory}/dotfiles/tmux/tmux-nix.conf";
  };

}

