for the context-mode plugin in the repo page https://github.com/mksglu/context-mode it says that for opencode we must install the plugin globally  with the commadn npm install -g context-mode. This conflicts with NixOS how can we solve the problem?

- ● Two separate issues: 
1. MCP server — needs context-mode binary in PATH 
2. Plugin entry — opencode manages plugin installation itself to its own dir, unrelated to global npm For the binary, three options: 
 - A) Quick fix — change MCP command to use npx: "context-mode" = { type = "local"; command = ["npx" "-y" "context-mode"]; }; Downloads on first run. Works. Not pure Nix. 
 - B) Nix wrapper (no hash needed): let context-mode = pkgs.writeShellScriptBin "context-mode" '' exec ${pkgs.nodejs}/bin/npx --yes context-mode "$@" ''; in Add to programs.opencode.extraPackages. Binary exists in PATH, npx handles download. 
 - C) Proper buildNpmPackage derivation — needs npmDepsHash, most correct but requires fetching the hash first. Recommendation: option B — creates a real binary, avoids changing the MCP command string, opencode sees context-mode in PATH normally. Want me to apply option B to opencode.nix?

