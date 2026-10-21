# WSL secrets: decrypted by the sops-nix systemd user service into
# /run/user/1000/secrets.d and linked at ~/.config/sops-nix/secrets/<name>.
# Each WSL instance has its own generated age key; wsl/.sops.yaml lists every
# instance's public key. All four keys must exist in the file, otherwise
# sops-install-secrets fails the whole service.
{ config, ... }:
{
  sops = {
    age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
    defaultSopsFile = ../secrets/secrets.yaml;
    defaultSopsFormat = "yaml";
    secrets = {
      github_pat = { };
      openrouter = { };
      opencode = { };
      cheaper_inference = { };
    };
  };
}
