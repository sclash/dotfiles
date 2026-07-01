{
  config,
  lib,
  pkgs,
  unstable-pkgs,
  # my-dotfiles,
  ...
}:

{

  programs.pandoc = {
    enable = true;
    package = pkgs.pandoc;
    defaults = {
      pdf-engine = "xelatex";
    };
  };

  home.packages = [ pkgs.texlive.combined.scheme-small ];
}
