{ config, lib, pkgs, unstable-pkgs, my-dotfiles, ... }:

{

  programs.tmux = {
    enable = true;
    plugins = with pkgs.tmuxPlugins; [
      sensible
      continuum
      resurrect
	rose-pine
	tmux-sessionx
			# tokyo-night-tmux
    ];
    # extraConfig = builtins.readFile /home/asergi/dotfiles/tmux/tmux.conf;
    extraConfig = builtins.readFile "${my-dotfiles}/tmux/tmux-nix.conf";
  };

}

