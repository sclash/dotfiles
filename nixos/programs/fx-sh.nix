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

  # fx opens ~/.fx/settings.json with O_NOFOLLOW, rejects hard links, and saves
  # settings with a temp file + rename. A home-manager symlink at that path is
  # therefore rejected (or replaced on the first write), so the wrapper copies
  # the repo file into a real, private file first and writes changes back
  # through the symlink after fx exits.
  #
  # Everything else under ~/.fx that is configuration, rather than runtime
  # state, is linked directly below: fx follows those.
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
      if [ -L "$dst" ] || [ "$links" -ne 1 ] || [ ! -f "$dst" ] || [ "$src" -nt "$dst" ]; then
        install -m 600 "$src" "$dst"
      fi
    fi

    # Remember what fx starts from, so only changes made during this run are
    # written back to the repo.
    snap=""
    if [ -f "$dst" ]; then
      snap="$(mktemp)" || snap=""
      if [ -n "$snap" ]; then cp -p "$dst" "$snap"; fi
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

    # fx follows this for reads but refuses to edit a linked file, so /mcp add
    # and /mcp remove will fail; edit the repo and restart fx instead.
    ".fx/mcp.json".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/fx/mcp.json";
  };
}
