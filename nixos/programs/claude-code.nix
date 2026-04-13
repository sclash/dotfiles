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
	# nix-prefetch-git --url https://github.com/anthropics/claude-plugins-official
	# to get the sha256 from the last commit from main

    marketplaces = {
      claude-plugins-official = pkgs.fetchFromGitHub {
        owner = "anthropics";
        repo = "claude-plugins-official";
        # rev = "7ed523140f506611c968a0ec32e1dfc40a1d5673";
        rev = "main";
        sha256 = "1bj6s86a8mdpg7f7fy2ifmchpc73vmh5bpsyqb2xzfy4grryfncs";
        # sha256 = lib.fakeHash;
      };
      thedotmack = pkgs.fetchFromGitHub {
        owner = "thedotmack";
        repo = "claude-mem";
        rev = "cde4faae2f33f92d2092ca87537b17b837fdcfb7";
        sha256 = "1iarxmaaml4xqpz84cx8lz3finmiiacmrdcx2p61ikygai0gwh2a";
      };
      context-mode = pkgs.fetchFromGitHub {
        owner = "mksglu";
        repo = "context-mode";
        rev = "d6286730878816b82dfd5c245d34fab0241d41c7";
        sha256 = "1p530wcvc3mwmvv73r1xbsqz1s69hqgpbvpnd69bwn47hl9y16nl";
      };
    };
    plugins = [
      (pkgs.fetchFromGitHub {
        owner = "thedotmack";
        repo = "claude-mem";
        rev = "cde4faae2f33f92d2092ca87537b17b837fdcfb7";
        sha256 = "1iarxmaaml4xqpz84cx8lz3finmiiacmrdcx2p61ikygai0gwh2a";
      })

      (pkgs.fetchFromGitHub {
        owner = "mksglu";
        repo = "context-mode";
        rev = "d6286730878816b82dfd5c245d34fab0241d41c7";
        sha256 = "1p530wcvc3mwmvv73r1xbsqz1s69hqgpbvpnd69bwn47hl9y16nl";
      })
      (let
        claude-plugins-official = pkgs.fetchFromGitHub {
          owner = "anthropics";
          repo = "claude-plugins-official";
          rev = "main";
          sha256 = "1bj6s86a8mdpg7f7fy2ifmchpc73vmh5bpsyqb2xzfy4grryfncs";
        };
      in "${claude-plugins-official}/plugins/code-simplifier")
      (let
        claude-plugins-official = pkgs.fetchFromGitHub {
          owner = "anthropics";
          repo = "claude-plugins-official";
          rev = "main";
          sha256 = "1bj6s86a8mdpg7f7fy2ifmchpc73vmh5bpsyqb2xzfy4grryfncs";
        };
      in "${claude-plugins-official}/plugins/code-review")
    ];
  };
}

