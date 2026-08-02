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
    rev = "d620fb7d8349b66bbe281ea74cd346287abb6a48";
    sha256 = "14340nvprnam4ri51wcjdzrsxc9xd0sl2syj12gid1p1xak29ma5";
  };
  superpowers = pkgs.fetchFromGitHub {
    owner = "obra";
    repo = "superpowers";
    rev = "44c9b2d6e889982ac18c27d05a19fefe335194e1";
    sha256 = "0xsx1ns30l084j3wqlmsmd54jcdnbi9npz0ccvws1nnbncfpwyby";
  };
  ecc = pkgs.fetchFromGitHub {
    owner = "affaan-m";
    repo = "ECC";
    rev = "e4e4163101f162881e628f300a9ca4e6a940bcea";
    sha256 = "0r6dqb5wxd98w390famwn4j2z0fd3hxl2dz03423x6lb6s0hqlgf";
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
    rev = "a90066f9cf82cc936dd2d841319bb6b19658f7d4";
    sha256 = "1rl03shf7afi5d4rw2nbji9zjrcn0djjqi3998cdzi0jgi6qj637";
  };
  context-mode = pkgs.fetchFromGitHub {
    owner = "mksglu";
    repo = "context-mode";
    rev = "e27c14331179507978fcc8fb75a2318ae647bf4a";
    sha256 = "1md12lsha4js4dbmvgl2yphr3b2rhha8y3rzp97m658wmql2lh33";
  };
  # Upstream shipped a self-referential `plugins/context-mode -> ..` symlink
  # that made opencode/claude recurse into an infinite symlink loop (ELOOP).
  # Strip it so generated generations never carry the loop.
  # context-mode-clean = pkgs.runCommand "context-mode-clean" { } ''
  #   cp -r --no-preserve=all ${context-mode} $out
  #   rm -f "$out/plugins/context-mode"
  # '';
  caveman = pkgs.fetchFromGitHub {
    owner = "JuliusBrussee";
    repo = "caveman";
    rev = "0d95a81d35a9f2d123a5e9430d1cfc43d55f1bb0";
    sha256 = "0sjk5l6gy1rs7chjv18dzhhim6vvw6gm1p0x2akj0jgqgz3lg92n";
  };
  wshobson-agents = pkgs.fetchFromGitHub {
    owner = "wshobson";
    repo = "agents";
    rev = "c4b82b0ad771190355eb8e204b1329732a18449a";
    sha256 = "05axmkblh6hq0q3czsyalksiwq1z5gvllp18sa6c499fgmsl3fpz";
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
        # context-mode-clean
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
      # context-mode-clean
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
