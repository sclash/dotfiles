# Identity for this machine, read from the environment.
#
# Switches must pass --impure. Explicit DOTFILES_USER/DOTFILES_HOME overrides
# win over the ambient environment, so sudo (HOME=/root) and the installer keep
# a non-standard account. Pure evaluation (nix flake check) cannot read the
# environment and falls back to the historical asergi layout so checks stay
# deterministic. WSL runs as the existing OS user and inherits it verbatim.
let
  getenv = name: builtins.getEnv name;

  overrideUser = getenv "DOTFILES_USER";
  overrideHome = getenv "DOTFILES_HOME";
  sudoUser = getenv "SUDO_USER";
  envUser = getenv "USER";
  envHome = getenv "HOME";

  username =
    if overrideUser != "" then
      overrideUser
    else if sudoUser != "" && sudoUser != "root" then
      sudoUser
    else if envUser != "" then
      envUser
    else
      "asergi";

  homeDirectory =
    if overrideHome != "" then
      overrideHome
    else if username == "root" then
      "/root"
    else if envHome == "" || envHome == "/root" then
      "/home/${username}"
    else
      envHome;
in
{
  inherit username homeDirectory;
  dotfiles = "${homeDirectory}/dotfiles";
}
