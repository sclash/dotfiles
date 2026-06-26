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
      openrouter = {
        type = "remote";
        enabled = true;
        url = "https://mcp.openrouter.ai/mcp";
      };
      playwright = {
        type = "local";
        enabled = false;
        disabled = true;
        command = "npx";
        args = [ "@playwright/mcp@latest" ];
      };
      shadcn-vue = {
        type = "local";
        enabled = false;
        disabled = true;
        command = "bunx";
        args = [
          "--bun"
          "shadcn-vue@latest"
          "mcp"
        ];
      };

      nixos = {
        type = "local";
        enabled = true;
        command = "mcp-nixos";
        args = [ ];
      };

      chrome-devtools = {
        type = "local";
        enabled = false;
        disabled = true;
        command = "npx";
        args = [
          "-y"
          "chrome-devtools-mcp@latest"
        ];
      };

      github = {
        type = "local";
        enabled = false;
        disabled = true;
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
        enabled = true;
        command = "npx";
        args = [
          "-y"
          "context-mode"
        ];
      };
    };
  };
}
