# opencode config from my-opencode/v2, with WSL copies from wsl/opencode.
# opencode itself comes from pkgs-unstable via wsl/packages.nix.
{ config, lib, ... }:
let
  v2 = import ../lib/v2-overlay.nix { inherit config lib; };
  items = [
    "opencode.jsonc"
    "AGENTS.md"
    "CLAUDE.md"
    "RIPWIRE.md"
    "agents"
    "commands"
    "instructions"
    "plugins"
    "prompts"
    "scripts"
    "skills"
    "tools"
  ];
in
{
  home.file =
    lib.mapAttrs' (rel: lib.nameValuePair ".config/opencode/${rel}") (
      lib.mergeAttrsList (map v2 items)
    )
    // {
      ".agents".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/.agents";
    };

  home.sessionVariables.OPENCODE_DISABLE_CLAUDE_CODE_SKILLS = "true";
}
