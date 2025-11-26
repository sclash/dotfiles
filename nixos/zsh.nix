{ config, lib, pkgs, unstable-pkgs, my-dotfiles, ... }:

{

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    autocd = true;
    syntaxHighlighting.enable = true;
    initExtra = ''
            	eval "$(starship init zsh)"
             	eval "$(atuin init zsh)"
      		'';
    # initExtra = ''
    #   [[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh
    # '';
    # plugins = [{
    #   name = "powerlevel10k";
    #   src = pkgs.zsh-powerlevel10k;
    #   file = "share/zsh-powerlevel10k/powerlevel10k.zsh-theme";
    # }];

    shellAliases = {
      ll = "ls -l";
      edit = "sudo -e";
      update = "sudo nixos-rebuild switch --flake /etc/nixos";
      ftm = "~/tmux-sessionizer.sh";
    };

    history.ignoreAllDups = true;
    history.path = "$HOME/.zsh_history";
    history.size = 10000;
    initContent = ''
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
    # oh-my-zsh = { # "ohMyZsh" without Home Manager
    #   enable = true;
    #   plugins = [ "git" ];
    #   # theme = "powerlevel10k";
    # };
  };
}

