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
    rev = "bef2b9b246e2072d167a71b7a8d65718ec55d2ef";
    sha256 = "1y83wgp737di6d4ldqll2n2svgsyq0d0qp09q0cs8llbhpyq7nfk";
  };
  superpowers = pkgs.fetchFromGitHub {
    owner = "obra";
    repo = "superpowers";
    rev = "f2cbfbefebbfef77321e4c9abc9e949826bea9d7";
    sha256 = "0g1j8k8kqm6zpjb5gdlzcc6r4gm3398mgmrdgmab5wsim0xynkfw";
  };
  ecc = pkgs.fetchFromGitHub {
    owner = "affaan-m";
    repo = "ECC";
    rev = "1e8c7e7994223e0ff337d1626cd08e04a1ae67ed";
    sha256 = "0fpj9rb8yhmqqfnz9qan6p2hxdg3rmx1ja3sy8pxv63c5bfi7icr";
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
    rev = "37d24944af5f4afaa0de2b0bd0034bb432f2b714";
    sha256 = "1kx2sh1sbshalnl25r1q67ggr01884a2j8v88gs074hnf0ml97pa";
  };
  context-mode = pkgs.fetchFromGitHub {
    owner = "mksglu";
    repo = "context-mode";
    rev = "55b51d31db397de04912a8d6953a094f4c388368";
    sha256 = "1lrk91hr7g6lhh221cfcp9c6xmxy0fvd3pr088cvv3jc74zdnqms";
  };
  caveman = pkgs.fetchFromGitHub {
    owner = "JuliusBrussee";
    repo = "caveman";
    rev = "84cc3c14fa1e10182adaced856e003406ccd250d";
    sha256 = "0s9ppf7qs5g5h7hrik4rlfdakwnkryp9mrggdpjdd1kbgicniqrk";
  };
  wshobson-agents = pkgs.fetchFromGitHub {
    owner = "wshobson";
    repo = "agents";
    rev = "08ded5e7b0fe57e7f40194775885eba539c3d8e7";
    sha256 = "0wh6ffb495zkakg5gr22na6dqa9jkgcjc74zkqrhpxr4xc4cnwfs";
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
        type = "stdio";
        command = "nix";
        args = [
          "run"
          "nixpkgs#markitdown-mcp"
        ];
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
      zig = {
        command = "zls";
        extensionToLanguage = {
          ".zig" = "zig";
        };
      };
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
        ecc
        context-mode
        caveman
        wshobson-agents
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
      # "${claude-plugins-official}/plugins/data-engineering"
      "${claude-plugins-official}/external_plugins/playwright"
      superpowers
      # firecrawl
      claude-mem
      context-mode
      caveman
      wshobson-agents
      "${wshobson-agents}/plugins/data-engineering"
      ecc
    ];

    # ".claude/skills/explore-codebase" = {
    #   source = config.lib.file.mkOutOfStoreSymlink "/home/asergi/dotfiles/.claude/explore-codebase";
    #   force = true;
    # };
  };
}
