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
        enabled = false;
        disabled = true;
        command = "markitdown-mcp";
        args = [ ];
      };
      openrouter = {
        type = "remote";
        enabled = false;
        disabled = true;
        url = "https://mcp.openrouter.ai/mcp";
      };
      hf-mcp-server = {
        type = "remote";
        enabled = false;
        disabled = true;
	url = "https://huggingface.co/mcp?login";
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
        enabled = false;
        disabled = true;
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
          GITHUB_PERSONAL_ACCESS_TOKEN = "{env:GITHUB_PERSONAL_ACCESS_TOKEN}";
        };
      };

      filesystem = {
        type = "local";
        enabled = false;
        disabled = true;
        command = "npx";
        args = [
          "-y"
          "@modelcontextprotocol/server-filesystem"
          "${config.home.homeDirectory}/"
          "${config.home.homeDirectory}/hacking/"
          "${config.home.homeDirectory}/Downloads/"
        ];
      };

      context-mode = {
        type = "local";
        enabled = true;
        disabled = true;
        command = "npx";
        args = [
          "-y"
          "context-mode"
        ];
      };
    };
  };
}
