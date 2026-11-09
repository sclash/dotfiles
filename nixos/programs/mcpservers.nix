{ config, ... }:

# Single source of truth for MCP servers, shared by Claude Code and OpenCode
# through their `enableMcpIntegration` options.
#
# Write entries in Home Manager's neutral shape, never in a client's own shape:
#   local server:  command + args (+ env / envFiles)
#   remote server: url
# Leave out `type`: each client module derives it from `url` (Claude Code
# stdio/http, OpenCode local/remote). Toggle a server with `disabled`.
#
# `disabled` only takes effect in OpenCode, which lists the server and lets
# you enable it mid-session. Claude Code receives these servers through Home
# Manager's `hm` plugin and starts them all: it ignores `disabledMcpjsonServers`
# for plugin servers.
#
# GITHUB_PERSONAL_ACCESS_TOKEN reaches the github server from the login
# environment (see home.nix), so it needs no `env` entry here.
let
  home = config.home.homeDirectory;
in
{
  programs.mcp = {
    enable = true;
    servers = {
      markitdown = {
        command = "nix";
        args = [
          "run"
          "nixpkgs#markitdown-mcp"
        ];
        disabled = true;
      };
      hf-mcp-server = {
        url = "https://huggingface.co/mcp?login";
        disabled = true;
      };
      ripwire = {
        command = "ripwire";
        args = [ "--mcp" ];
        disabled = true;
      };
      arxiv = {
        command = "uvx";
        args = [
          "--from"
          "arxiv-mcp-server[pdf]"
          "arxiv-mcp-server"
        ];
        disabled = true;
      };
      graphify = {
        command = "graphify-mcp";
        args = [ "./graphify-out/graph.json" ];
        disabled = true;
      };
      openrouter = {
        url = "https://mcp.openrouter.ai/mcp";
        disabled = true;
      };
      playwright = {
        command = "npx";
        args = [ "@playwright/mcp@latest" ];
        disabled = true;
      };
      # The bunx variant is kept as a comment, as in the V1 opencode file:
      # shadcn-vue = {
      #   command = "bunx";
      #   args = [
      #     "--bun"
      #     "shadcn-vue@latest"
      #     "mcp"
      #     "init"
      #     "--client"
      #     "opencode"
      #   ];
      #   disabled = true;
      # };
      shadcn-vue = {
        command = "npx";
        args = [
          "shadcn-vue@latest"
          "mcp"
        ];
        disabled = true;
      };
      nixos = {
        command = "nix";
        args = [
          "run"
          "github:utensils/mcp-nixos"
          "--"
        ];
        disabled = true;
      };
      chrome-devtools = {
        command = "npx";
        args = [
          "-y"
          "chrome-devtools-mcp@latest"
        ];
        disabled = true;
      };
      github = {
        command = "nix";
        args = [
          "run"
          "nixpkgs#github-mcp-server"
          "--"
          "stdio"
        ];
        disabled = true;
      };
      filesystem = {
        command = "npx";
        args = [
          "-y"
          "@modelcontextprotocol/server-filesystem"
          "${home}/"
          "${home}/hacking/"
          "${home}/Downloads/"
        ];
        disabled = true;
      };
    };
  };
}
