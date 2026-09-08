{
  config,
  lib,
  pkgs,
  pkgs-unstable,
  pkgs-master,
  # my-dotfiles,
  ...
}:

{
  programs.nushell = {
    enable = true;
    package = pkgs-unstable.nushell;
    # plugins = with pkgs; [
    # 	nushellPlugins.formats
    # 	nushellPlugins.polars
    # 	nushellPlugins.gstat
    # 	nushellPlugins.highlight
    # 	nushellPlugins.dbus
    # 	nushellPlugins.net
    # 	nushellPlugins.desktop_notifications
    # ];
    extraConfig = "
    		$env.config.edit_mode = 'vi'
	";
  };
  # home.file = {
  #   ".config/nushell/config.nu" = {
  #     source = config.lib.file.mkOutOfStoreSymlink "/home/asergi/dotfiles/config.nu";
  #     force = true;
  #   };
  # };
}
