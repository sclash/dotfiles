{ config, lib, pkgs, unstable-pkgs, ... }:

{

  programs.tmux = {
    enable = true;
    plugins = with pkgs.tmuxPlugins; [ tilish sensible tokyo-night-tmux ];
    # extraConfig = builtins.readFile /home/asergi/dotfiles/tmux/tmux.conf;
  };

}

