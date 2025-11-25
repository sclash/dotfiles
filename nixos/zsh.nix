{ config, lib, pkgs, unstable-pkgs, my-dotfiles, ... }:

{

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestions.enable = true;
    syntaxHighlighting.enable = true;

    shellAliases = {
      ll = "ls -l";
      edit = "sudo -e";
      update = "sudo nixos-rebuild switch --flake /etc/nixos";
      ftm = "~/tmux-sessionizer.sh";
    };

    histSize = 10000;
    histFile = "$HOME/.zsh_history";
    setOptions = [ "HIST_IGNORE_ALL_DUPS" ];
    promptInit = ''
      show_eza_tree() {
      	level_arg=''${1:-2}
      	eza --tree --level="$level_arg" --long --icons --git
      }

      alias lz='show_eza_tree'

            # uncomment if you want to customize your LS_COLORS
            # https://manpages.ubuntu.com/manpages/plucky/en/man5/dir_colors.5.html
            #LS_COLORS='...'
            #export LS_COLORS
    '';
  };
    oh-my-zsh = { # "ohMyZsh" without Home Manager
      enable = true;
      plugins = [ "git" ];
      # theme = "robbyrussell";
      theme = "powerlevel10k";
    };
}

