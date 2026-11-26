{
  config,
  lib,
  pkgs,
  pkgs-master,
  dotfiles,
  ...
}:
let
  # The out-of-store hand-off point. fx refuses symlinked settings, so the
  # launcher below materializes this file into a real ~/.fx/settings.json.
  fxSettings = "${dotfiles}/fx/settings.json";

  # MCP servers are defined once in nixos/programs/mcpservers.nix and shared
  # with OpenCode/Claude. Convert the neutral shape to fx's mcp.json shape,
  # keeping `disabled` as `"enabled": false` so every server stays off until
  # it is turned on. The tracked override file applies per-server patches at
  # launch without a rebuild.
  mcpEnabled = server: if server.enabled != null then server.enabled else !server.disabled;
  toFxMcp =
    _name: server:
    if server.url != null then
      {
        type = "http";
        inherit (server) url;
        enabled = mcpEnabled server;
      }
    else
      {
        type = "stdio";
        command = [ server.command ] ++ server.args;
        enabled = mcpEnabled server;
      }
      // lib.optionalAttrs (server.env != { }) { env = server.env; };

  fxMcpBase = (pkgs.formats.json { }).generate "fx-mcp-base.json" {
    mcpServers = lib.mapAttrs toFxMcp config.programs.mcp.servers;
  };

  # fx opens ~/.fx/settings.json with O_NOFOLLOW, rejects hard links, and saves
  # settings with a temp file + rename. A home-manager symlink at that path is
  # therefore rejected (or replaced on the first write), so the wrapper copies
  # the repo file into a real, private file first and writes changes back
  # through the symlink after fx exits.
  #
  # Agents, themes and AGENTS.md are linked directly below: fx follows those.
  # MCP servers are generated from mcpservers.nix and merged with a tracked
  # override at launch, because fx needs a real (non-link) mcp.json.
  fx = pkgs.writeShellScriptBin "fx" ''
    set -eu

    src="$HOME/.config/fx/settings.json"
    dst="$HOME/.fx/settings.json"

    if [ -f "$src" ]; then
      mkdir -p "$HOME/.fx"
      # Also replace a stale symlink or hard link left by an earlier attempt;
      # fx rejects both.
      links=1
      if [ -f "$dst" ]; then
        links="$(stat -c %h "$dst" 2>/dev/null || echo 1)"
      fi
      if [ -L "$dst" ] || [ "$links" -ne 1 ] || [ ! -f "$dst" ] || ! cmp -s "$src" "$dst"; then
        install -m 600 "$src" "$dst"
      fi
    fi

    # MCP servers are generated from nixos/programs/mcpservers.nix. Apply the
    # tracked override file so a server can be enabled without a rebuild.
    # fx reads a real file here; it cannot edit a link.
    mkdir -p "$HOME/.fx"
    over="$HOME/.config/fx/mcp.overrides.json"
    merged="$(mktemp 2>/dev/null || true)"
    if [ -n "$merged" ] && [ -f "$over" ] && ${lib.getExe pkgs.jq} -s '
        .[0] as $base
        | (.[1].mcpServers // {}) as $overrides
        | $base
        | .mcpServers |= with_entries(.value += ($overrides[.key] // {}))
      ' "${fxMcpBase}" "$over" > "$merged" 2>/dev/null; then
      install -m 600 "$merged" "$HOME/.fx/mcp.json"
    else
      if [ -n "$merged" ] && [ -f "$over" ]; then
        echo "fx: could not merge $over; using the generated MCP servers" >&2
      fi
      install -m 600 "${fxMcpBase}" "$HOME/.fx/mcp.json"
    fi
    [ -z "$merged" ] || rm -f "$merged"

    # Remember what fx starts from, so only changes made during this run are
    # written back to the repo.
    snap=""
    if [ -f "$dst" ]; then
      snap="$(mktemp)" || snap=""
      if [ -n "$snap" ]; then cp -p "$dst" "$snap"; fi
    fi

    # OpenCode Go rejects coding-agent requests without a stable
    # per-conversation session id. fx does not send one itself, so give it a
    # fresh id per launch. The opencode-go connection reads this through its
    # "headers" entry in fx/settings.json.
    if [ -z "''${FX_OPENCODE_SESSION:-}" ]; then
      FX_OPENCODE_SESSION="$(cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "fx-$$-$(date +%s)")"
      export FX_OPENCODE_SESSION
    fi

    status=0
    ${lib.getExe pkgs-master.fx-sh} "$@" || status=$?

    if [ -n "$snap" ] && [ -f "$dst" ] && ! cmp -s "$snap" "$dst"; then
      if [ -L "$src" ]; then
        cat "$dst" > "$src"
      else
        echo "fx: $src is not the home-manager symlink; settings were not written back" >&2
      fi
    fi

    [ -z "$snap" ] || rm -f "$snap"
    exit "$status"
  '';
in
{
  # Shadow the fx-sh package from configuration.nix. ~/.nix-profile/bin comes
  # before /run/current-system/sw/bin on PATH, so `fx` runs the wrapper.
  home.packages = [ fx ];

  home.file = {
    # settings.json is the only file fx refuses to read through a link; it is
    # synced by the launcher above.
    ".config/fx/settings.json".source =
      config.lib.file.mkOutOfStoreSymlink fxSettings;

    # fx follows these, so they can stay live out-of-store links. The agents
    # directory must be the link, not an individual profile: fx only lists
    # profile entries whose kind is directory, while the agents root itself is
    # opened with symlink following.
    ".fx/agents".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/fx/agents";
    ".fx/themes".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/fx/themes";

    # ~/.fx/AGENTS.md may link to a file elsewhere in $HOME.
    ".fx/AGENTS.md".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/fx/AGENTS.md";

    # Servers come from nixos/programs/mcpservers.nix; the launcher merges this
    # override on top and writes a real ~/.fx/mcp.json. Add entries here to
    # enable a server without rebuilding, for example:
    #   { "mcpServers": { "playwright": { "enabled": true } } }
    ".config/fx/mcp.overrides.json".source =
      config.lib.file.mkOutOfStoreSymlink "${dotfiles}/fx/mcp.overrides.json";
  };
}
