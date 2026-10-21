# overlay-links preconfigured for my-opencode/v2 (base) + wsl/opencode
# (WSL copies of the v2 files that conflict with this host). Shared by the
# opencode and claude-code modules.
{ config, lib }:
let
  home = config.home.homeDirectory;
in
import ./overlay-links.nix { inherit lib; } {
  link = config.lib.file.mkOutOfStoreSymlink;
  baseSrc = ../../my-opencode/v2;
  overlaySrc = ../opencode;
  baseLive = "${home}/dotfiles/my-opencode/v2";
  overlayLive = "${home}/dotfiles/wsl/opencode";
  # Points LD_LIBRARY_PATH at NixOS's nix-ld dir, which doesn't exist here.
  exclude = [ "plugins/nix-ld-env.js" ];
}
