{ config, lib, pkgs, pkgs-master, ... }:

{
  programs.claude-code = {
    enable = true;
    package = pkgs-master.claude-code;
    mcpServers = {
      nixos = {
        type = "stdio";
        command = "nix";
        args = [ "run" "github:utensils/mcp-nixos" "--" ];
      };
    };
  };
}

