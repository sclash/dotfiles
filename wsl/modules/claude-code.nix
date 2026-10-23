# Claude Code comes from pkgs-unstable via wsl/packages.nix and owns
# ~/.claude/settings.json. Only these skills are linked, from v2 with the WSL
# copies applied.
{ config, lib, ... }:
let
  v2 = import ../lib/v2-overlay.nix { inherit config lib; };
  skills = [
    "explore-codebase"
    "high-perf-systems"
    "download-video"
    "transcribe-media"
  ];
in
{
  home.file = lib.mapAttrs' (rel: lib.nameValuePair ".claude/${rel}") (
    lib.mergeAttrsList (map (s: v2 "skills/${s}") skills)
  );
}
