# CLI/TUI subset of nixos/home.nix and the environment.systemPackages in
# nixos/configuration.nix. GUI apps and NixOS-only system pieces are left out
# (see the spec's "Packages" and "configuration.nix coverage").
{
  lib,
  pkgs,
  pkgs-unstable,
  ...
}:
{
  # Headless chromium renders text with these; terminal fonts live on Windows.
  fonts.fontconfig.enable = true;

  home.packages =
    (with pkgs; [
      # Editors and Nix tools
      neovim
      vim
      tree-sitter
      nixd
      nix-prefetch-git
      sops
      age

      # CLI utilities
      tree
      bat
      eza
      fd
      jq
      zoxide
      zip
      unzip
      wget
      wl-clipboard # WSLg clipboard
      man-pages
      man-pages-posix

      # TUIs
      gh
      lazygit
      lazydocker
      lazysql
      lazyssh
      lazycli
      btop
      htop
      ncdu
      fastfetch
      glow
      hygg

      # Media and profiling
      ffmpeg
      timg
      chafa
      flamegraph
      hyperfine

      # Build and debug. gcc and clang both ship bin/cc; gcc wins.
      (lib.hiPrio gcc)
      llvmPackages_latest.clang
      llvmPackages_latest.lldb
      gdb
      valgrind
      bear
      gnumake
      pkg-config

      # Runtimes and libs
      lua
      nodejs
      typescript
      icu
      playwright

      # Browser (headless, for agent-browser and Playwright) and its fonts
      chromium
      noto-fonts
      noto-fonts-color-emoji

      (import ../nixos/programs/open-research.nix { inherit pkgs; })
    ])
    ++ (with pkgs-unstable; [
      ripgrep
      fzf
      universal-ctags
      python3
      bun
      go
      rustc
      cargo
      zig
      agent-browser
    ]);
}
