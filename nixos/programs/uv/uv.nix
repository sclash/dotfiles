{
  config,
  lib,
  pkgs,
  unstable-pkgs,
  # my-dotfiles,
  ...
}:

{

  programs.uv = {
    enable = true;
    package = pkgs.uv;

    # https://docs.astral.sh/uv/concepts/configuration-files/
    # List of available settings
    # https://docs.astral.sh/uv/reference/settings/#pip_python-platform
  #   settings = {
  #     pip = {
  #       python = "3.14.7";
  #       python-version = "3.12";
  #     };
  #   };
  };
	## Comment settings above and above this below to have the uv configuration outOfStore
  home.file = {
    ".config/uv/uv.toml" = {
      source = config.lib.file.mkOutOfStoreSymlink "/home/asergi/dotfiles/nixos/programs/uv/uv.toml";
      force = true;
    };
  };
}
