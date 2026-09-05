# Neovim language servers, formatters and debug adapters.
#
# Replaces mason.nvim / mason-lspconfig.nvim / mason-tool-installer.nvim /
# mason-nvim-dap.nvim: everything the editor needs is declared here, and the
# nvim config resolves binaries from PATH (see neovimrc after/plugin/lsp.lua
# and after/plugin/nvimdap.lua).
#
# NOTE: rebuild required after changes:
#   sudo nixos-rebuild switch --flake .#nixos
{
  config,
  lib,
  pkgs,
  ...
}:

let
  # codelldb (C/C++/Rust/Zig debug adapter) lives inside the vscode-lldb
  # extension; expose it on PATH so nvim-dap can find it via exepath().
  vscode-lldb = pkgs.vscode-extensions.vadimcn.vscode-lldb;
  codelldb = pkgs.writeShellScriptBin "codelldb" ''
    exec "${vscode-lldb}/share/vscode/extensions/vadimcn.vscode-lldb/adapter/codelldb" "$@"
  '';

  # debugpy adapter: python env with debugpy, exposed as a stdio DAP adapter.
  debugpy-env = pkgs.python3.withPackages (ps: [ ps.debugpy ]);
  debugpy-adapter = pkgs.writeShellScriptBin "debugpy-adapter" ''
    exec "${debugpy-env}/bin/python" -m debugpy.adapter "$@"
  '';
in
{
  home.packages =
    (with pkgs; [
      # --- LSP servers (replaces mason-lspconfig ensure_installed) ---
      vtsls
      vue-language-server
      bash-language-server
      rust-analyzer
      pyright
      clang-tools
      lua-language-server
      tailwindcss-language-server
      vscode-langservers-extracted
      astro-language-server
      dockerfile-language-server-nodejs
      docker-compose-language-service
      zls
      markdown-oxide
      texlab
      emmet-language-server
      gopls

      # --- Formatters (replaces mason-tool-installer ensure_installed) ---
      prettier
      black

      # --- DAP adapters (replaces mason-nvim-dap ensure_installed) ---
      delve
      vscode-js-debug
    ])
    ++ [
      codelldb
      debugpy-adapter
    ];
}
