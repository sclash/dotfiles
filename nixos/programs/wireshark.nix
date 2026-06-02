{
  config,
  lib,
  pkgs,
  unstable-pkgs,
  # my-dotfiles,
  ...
}:

{

  programs.wireshark = {
    enable = true;
    usbmon.enable = true;
    dumpcap.enable = true;
  };
}
