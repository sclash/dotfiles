# WSL copy of nixos/programs/zsh.nix: home-manager instead of nixos-rebuild,
# and secrets from sops-nix's home-manager paths instead of /run/secrets.
{ config, ... }:
let
  gh = config.sops.secrets.github_pat.path;
  openrouter = config.sops.secrets.openrouter.path;
in
{
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    autocd = true;
    syntaxHighlighting.enable = true;

    shellAliases = {
      ll = "ls -l";
      edit = "sudo -e";
      update = "home-manager switch --flake ~/dotfiles/wsl#asergi -b hm-backup";
      ftm = "${config.home.homeDirectory}/dotfiles/scripts/tmux-sessionizer.sh";
    };

    history.ignoreAllDups = true;
    history.path = "$HOME/.zsh_history";
    history.size = 10000;

    # Secrets may not be decrypted yet (first login, or no key on this
    # instance), so every read is guarded.
    initContent = ''
      if [ -f ${gh} ]; then export GITHUB_PERSONAL_ACCESS_TOKEN="$(cat ${gh})"; fi
      if [ -f ${openrouter} ]; then export OPENROUTER_API="$(cat ${openrouter})"; fi

      show_eza_tree() {
        level_arg=''${1:-2}
        eza --tree --level="$level_arg" --long --icons --git
      }

      alias lz='show_eza_tree'
    '';
  };
}
