{
  config,
  lib,
  pkgs,
  ...
}:

{
  programs.mcp = {
    enable = true;
    servers = {

      markitdown = {
        type = "local";
        enabled = true;
        command = "markitdown-mcp";
        args = [ ];
      };

      playwright = {
        type = "local";
        enabled = true;
        command = "npx";
        args = [ "@playwright/mcp@latest" ];
      };

      shadcn-vue = {
        type = "local";
        enabled = true;
        command = "bunx";
        args = [ "--bun" "shadcn-vue@latest" "mcp" ];
      };

      nixos = {
        type = "local";
        enabled = true;
        command = "mcp-nixos";
        args = [ ];
      };

      chrome-devtools = {
        type = "local";
        enabled = true;
        command = "npx";
        args = [
          "-y"
          "chrome-devtools-mcp@latest"
        ];
      };

      github = {
        type = "local";
        enabled = true;
        command = "npx";
        args = [
          "-y"
          "@modelcontextprotocol/server-github"
        ];
        environment = {
          GITHUB_PERSONAL_ACCESS_TOKEN = "{env:GITHUB_TOKEN}";
        };
      };

      filesystem = {
        type = "local";
        enabled = true;
        command = "npx";
        args = [
          "-y"
          "@modelcontextprotocol/server-filesystem"
          "/home/asergi/"
          "/home/asergi/hacking/"
          "/home/asergi/Downloads/"
        ];
      };

      context-mode = {
        type = "local";
        command = "npx";
        args = [
          "-y"
          "context-mode"
        ];
      };
    };
  };
}
