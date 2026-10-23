# WSL secrets: decrypted by the sops-nix systemd user service into
# /run/user/<uid>/secrets.d and linked at ~/.config/sops-nix/secrets/<name>.
# Each WSL instance has its own generated age key; wsl/.sops.yaml lists every
# instance's public key. All four keys must exist in the file, otherwise
# sops-install-secrets fails the whole service.
#
# DOTFILES_WSL_SECRETS can point at a per-instance local file created by
# `bootstrap.sh --new-secrets`; otherwise the shared committed file is used.
# The override must be an absolute path to an existing, sops-encrypted file.
{ config, ... }:
let
  override = builtins.getEnv "DOTFILES_WSL_SECRETS";
  localSecrets =
    if override == "" then null
    else if builtins.substring 0 1 override != "/" then
      throw "DOTFILES_WSL_SECRETS must be an absolute path"
    else
      /. + override;
in
{
  sops = {
    age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
    defaultSopsFile =
      if localSecrets == null then ../secrets/secrets.yaml
      else if !(builtins.pathExists localSecrets) then
        throw "DOTFILES_WSL_SECRETS does not exist: ${override}"
      else if builtins.readFileType localSecrets != "regular" then
        throw "DOTFILES_WSL_SECRETS must be a regular file: ${override}"
      else localSecrets;
    defaultSopsFormat = "yaml";
    secrets = {
      github_pat = { };
      openrouter = { };
      opencode = { };
      cheaper_inference = { };
    };
  };
}
