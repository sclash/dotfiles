{ config, lib, pkgs, pkgs-unstable, ... }:

{
  programs.claude-code = {
    enable = true;
    package = pkgs-unstable.claude-code;
    mcpServers = {
      nixos = {
        type = "stdio";
        command = "nix";
        args = [ "run" "github:utensils/mcp-nixos" "--" ];
      };
    };
  };
}

