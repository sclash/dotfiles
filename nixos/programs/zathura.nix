{ config, lib, pkgs, unstable-pkgs, my-dotfiles, ... }:

{

  programs.zathura = {
    enable = true;
		options = {
			selection-clipboard = "clipboard";
		};
  };
}
