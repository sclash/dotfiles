{ config, lib, pkgs, unstable-pkgs, my-dotfiles, ... }:

{

  programs.tmux = {
    enable = true;
    terminal = "tmux-256color";
    keyMode = "vi";

    plugins = with pkgs.tmuxPlugins; [
      sensible
      {
        plugin = resurrect;
        extraConfig = "set -g @resurrect-strategy-nvim 'session'";
      }
      {
        plugin = continuum;
        extraConfig = ''
          set -g @continuum-restore 'on'
          set -g @continuum-save-interval '60' # minutes
        '';
      }
      tmux-fzf
      tmux-sessionx
      # rose-pine-unstable
      # tokyo-night-tmux
    ];
    # extraConfig = builtins.readFile "${my-dotfiles}/nixos/tmux/tmux.conf";
    extraConfig = builtins.readFile "${config.home.homeDirectory}/dotfiles/nixos/programs/tmux/tmux.conf";
    # extraConfig = builtins.readFile
    #   "${config.home.homeDirectory}/dotfiles/tmux/tmux-nix.conf";
    #  extraConfig = ''
    #                	set -ga terminal-overrides ",*:RGB"
    #                      set -g set-clipboard on
    #
    # set -g base-index 1
    # set -g pane-base-index 1
    # set-window-option -g pane-base-index 1
    # set-option -g renumber-windows on
    #
    #                      # Vim-like copy/paste
    #                      set-window-option -g mode-keys vi
    #                      bind-key -T copy-mode-vi v send-keys -X begin-selection
    #                      bind-key -T copy-mode-vi C-v send-keys -X rectangle-toggle
    #                      bind-key -T copy-mode-vi y send-keys -X copy-selection-and-cancel
    #                      unbind -T copy-mode-vi MouseDragEnd1Pane
    #
    #                      # Alt+hjkl to switch panes (vim-style)
    #                      bind -n M-h select-pane -L
    #                      bind -n M-j select-pane -D
    #                      bind -n M-k select-pane -U
    #                      bind -n M-l select-pane -R
    #
    #                      bind -n M-d previous-window
    #                      bind -n M-u next-window
    #                      # Alt+number to select window
    #    		  # don't work because captured by ghostty
    #
    #                      # bind -n M-1 select-window -t 1
    #                      # bind -n M-2 select-window -t 2
    #                      # bind -n M-3 select-window -t 3
    #                      # bind -n M-4 select-window -t 4
    #                      # bind -n M-5 select-window -t 5
    #                      # bind -n M-6 select-window -t 6
    #                      # bind -n M-7 select-window -t 7
    #                      # bind -n M-8 select-window -t 8
    #                      # bind -n M-9 select-window -t 9
    #                      		'';
    # extraConfig = builtins.readFile /home/asergi/dotfiles/tmux/tmux.conf;
    # extraConfig = builtins.readFile "/home/asergi/dotfiles/tmux/tmux-nix.conf";
    # extraConfig = builtins.readFile "${my-dotfiles}/tmux/tmux-nix.conf";
    # extraConfig = builtins.readFile
    #   "${config.home.homeDirectory}/dotfiles/tmux/tmux-nix.conf";
  };

}

