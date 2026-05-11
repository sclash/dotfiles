{
  config,
  lib,
  pkgs,
  pkgs-master,
  pkgs-unstable,
  ...
}:

let
  # nix-prefetch-git --url https://github.com/anthropics/claude-plugins-official
  # to get the sha256 from the last commit from main
  claude-plugins-official = pkgs.fetchFromGitHub {
    owner = "anthropics";
    repo = "claude-plugins-official";
    rev = "main";
    sha256 = "1bj6s86a8mdpg7f7fy2ifmchpc73vmh5bpsyqb2xzfy4grryfncs";
  };
  superpowers = pkgs.fetchFromGitHub {
    owner = "obra";
    repo = "superpowers";
    rev = "main";
    sha256 = "0yhvgwadr54njmyn82yxvf8sfwkwr8aw5myv7l7aw2q1aglrgihl";
  };
  # firecrawl = pkgs.fetchFromGitHub {
  #   owner = "firecrawl";
  #   repo = "firecrawl-claude-plugin";
  #   rev = "main";
  #   sha256 = "151z0696z32027zkqyy2hvmnhdnf9k7zd2wddgybnnyk3s431244";
  # };
  claude-mem = pkgs.fetchFromGitHub {
    owner = "thedotmack";
    repo = "claude-mem";
    rev = "main";
    sha256 = "1iarxmaaml4xqpz84cx8lz3finmiiacmrdcx2p61ikygai0gwh2a";
  };
  context-mode = pkgs.fetchFromGitHub {
    owner = "mksglu";
    repo = "context-mode";
    rev = "main";
    sha256 = "061kz73r12wclyzn95kv5vk94khvr9054i26fik7mfvjqj7xs6hi";
  };
  caveman = pkgs.fetchFromGitHub {
    owner = "JuliusBrussee";
    repo = "caveman";
    rev = "84cc3c14fa1e10182adaced856e003406ccd250d";
    sha256 = "0s9ppf7qs5g5h7hrik4rlfdakwnkryp9mrggdpjdd1kbgicniqrk";
  };
in
{
  programs.claude-code = {
    enable = true;
    package = pkgs-master.claude-code;
    settings = {
      theme = "dark";
      teammateMode = "tmux";
      env = {
        CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1";
      };
    };
    mcpServers = {
      markitdown = {
        command = "markitdown-mcp";
      };
      nixos = {
        type = "stdio";
        command = "mcp-nixos";
      };
      chrome-devtools = {
        type = "stdio";
        command = "npx";
        args = [
          "-y"
          "chrome-devtools-mcp@latest"
        ];
      };
      github = {
        type = "stdio";
        command = "npx";
        args = [
          "-y"
          "@modelcontextprotocol/server-github"
        ];
        env = {
          ## To get the token github->settinsg->developer settings
          GITHUB_PERSONAL_ACCESS_TOKEN = lib.strings.trim (
            builtins.readFile /home/asergi/dotfiles/nixos/.secrets/github_token
          );
        };
      };
      filesystem = {
        command = "npx";
        args = [
          "-y"
          "@modelcontextprotocol/server-filesystem"
          "/home/asergi/Downloads"
          "/home/asergi/dotfiles"
          "/home/asergi/hacking"
        ];
      };
    };
    lspServers = {
      go = {
        args = [ "serve" ];
        command = "gopls";
        extensionToLanguage = {
          ".go" = "go";
        };
      };
      python = {
        args = [ "--stdio" ];
        command = "pyright-langserver";
        extensionToLanguage = {
          ".py" = "python";
          ".pyi" = "python";
        };
      };
      clangd = {
        args = [ "--background-index" ];
        command = "clangd";
        extensionToLanguage = {
          ".c" = "c";
          ".h" = "c";
          ".cpp" = "cpp";
          ".cc" = "cpp";
          ".cxx" = "cpp";
          ".hpp" = "cpp";
          ".hxx" = "cpp";
          ".C" = "cpp";
          ".H" = "cpp";
        };
      };
      rust = {
        args = [ "--stdio" ];
        command = "rust-analyzer";
        extensionToLanguage = {
          ".rs" = "rust";
        };
      };
      vue = {
        args = [ "--stdio" ];
        command = "vue-language-server";
        extensionToLanguage = {
          ".vue" = "vue";
        };
      };
      tailwind = {
        args = [ "--stdio" ];
        command = "tailwind-language-server";
        extensionToLanguage = {
          ".vue" = "vue";
          ".css" = "css";
          ".html" = "html";
          ".ts" = "typescript";
          ".tsx" = "typescriptreact";
          ".js" = "javascript";
          ".jsx" = "javascriptreact";
          ".mts" = "typescript";
          ".cts" = "typescript";
          ".mjs" = "javascript";
          ".cjs" = "javascript";
        };
      };
      lua = {
        args = [ "--stdio" ];
        command = "lua-language-server";
        extensionToLanguage = {
          ".lua" = "lua";
        };
      };
      typescript = {
        args = [ "--stdio" ];
        command = "typescript-language-server";
        extensionToLanguage = {
          ".ts" = "typescript";
          ".tsx" = "typescriptreact";
          ".js" = "javascript";
          ".jsx" = "javascriptreact";
          ".mts" = "typescript";
          ".cts" = "typescript";
          ".mjs" = "javascript";
          ".cjs" = "javascript";
        };
      };
    };
    marketplaces = {
      inherit
        claude-plugins-official
        superpowers
        # firecrawl
        claude-mem
        context-mode
        caveman
        ;
    };
    plugins = [
      "${claude-plugins-official}/plugins/claude-code-setup"
      "${claude-plugins-official}/plugins/claude-md-management"
      "${claude-plugins-official}/plugins/code-simplifier"
      "${claude-plugins-official}/plugins/code-review"
      "${claude-plugins-official}/plugins/commit-commands"
      "${claude-plugins-official}/plugins/feature-dev"
      "${claude-plugins-official}/plugins/agent-sdk-dev"
      "${claude-plugins-official}/plugins/mcp-server-dev"
      "${claude-plugins-official}/plugins/plugin-dev"
      "${claude-plugins-official}/plugins/skill-creator"
      "${claude-plugins-official}/plugins/frontend-design"
      "${claude-plugins-official}/plugins/playground"
      "${claude-plugins-official}/plugins/learning-output-style"
      "${claude-plugins-official}/plugins/ralph-loop"
      "${claude-plugins-official}/external_plugins/playwright"
      superpowers
      # firecrawl
      claude-mem
      context-mode
      caveman
    ];
  };
}
