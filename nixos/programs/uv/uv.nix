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
    tool.packages = [
      "graphifyy"
      "graphifyy[mcp]"
      "skillevaluator[all] @ git+https://github.com/NVIDIA/SkillEvaluator.git"
    ];
    tool.prune = true;

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
  # The generated activation script resets PATH to a minimal hardcoded set,
  # so `uv tool install` cannot see cc or python3 when compiling sdists
  # (e.g. fastuuid via litellm). Prepend them before the uvTool step.
  home.activation.uvToolBuildEnv = lib.hm.dag.entryBefore [ "uvTool" ] ''
    export PATH="${pkgs.gcc}/bin:${pkgs.python3}/bin:$PATH"
  '';
  ## Comment settings above and above this below to have the uv configuration outOfStore
  home.file = {
    ".config/uv/uv.toml" = {
      source = config.lib.file.mkOutOfStoreSymlink "/home/asergi/dotfiles/nixos/programs/uv/uv.toml";
      force = true;
    };
  };
}
