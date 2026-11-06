# Stands in for /etc/nixos during pure evaluation (`nix flake check`), which
# cannot read outside the repo. Never used on a real machine: --impure rebuilds
# import the machine's own files instead.
{
  nixpkgs.hostPlatform = "x86_64-linux";
  time.timeZone = "UTC";
  boot.loader.grub.enable = false;
  fileSystems."/" = {
    device = "/dev/disk/by-label/stub";
    fsType = "ext4";
  };
  system.stateVersion = "25.05";
}
