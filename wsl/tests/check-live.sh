#!/usr/bin/env bash
# Post-switch checks on a live WSL instance (runs as the user, not in the
# sandbox). Every probe runs in a login + interactive zsh, like a new
# terminal. Prints OK/FAIL/SKIP per line; exits 1 on any FAIL.
set -uo pipefail

failures=0
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

ok() { echo "OK   $*"; }
bad() {
  echo "FAIL $*"
  failures=$((failures + 1))
}
skip() { echo "SKIP $*"; }
check() {
  local desc=$1
  shift
  if "$@"; then ok "$desc"; else bad "$desc"; fi
}
starts_with() { [[ "$1" == "$2"* ]]; }
# A new terminal starts from a clean environment (PATH from /etc/environment),
# not from this script's: an inherited PATH and __ETC_PROFILE_NIX_SOURCED
# would hide what a fresh login actually gets.
CLEAN_PATH=$(sed -n 's/^PATH="\(.*\)"$/\1/p' /etc/environment)
lz() {
  env -i HOME="$HOME" USER="$USER" LOGNAME="$USER" TERM="${TERM:-xterm-256color}" \
    PATH="${CLEAN_PATH:-/usr/bin:/bin}" XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-}" \
    zsh -lic "$1" 2>/dev/null
}

PROFILE=/home/asergi/.nix-profile/bin/

# --- PATH: the Nix profile wins over apt, snap, rustup and nvm
for b in nvim tmux herdr rg go zig node cargo uv starship atuin chromium; do
  first=$(lz "whence -p $b")
  check "$b from the nix profile (${first:-not found})" starts_with "$first" "$PROFILE"
done
for pair in claude:/home/asergi/.local/bin/claude opencode:/home/asergi/.opencode/bin/opencode; do
  b=${pair%%:*} want=${pair#*:}
  first=$(lz "whence -p $b")
  if [[ -z "$first" ]]; then skip "$b not installed (native installer, outside the flake)"; else
    check "$b is the native install ($first)" [ "$first" = "$want" ]
  fi
done

# --- links resolve into ~/dotfiles, none dangle
for p in .config/nvim .config/starship .config/atuin .config/uv/uv.toml .config/herdr/config.toml; do
  rp=$(realpath -e "$HOME/$p" 2>/dev/null)
  check "~/$p -> ${rp:-missing}" starts_with "$rp" /home/asergi/dotfiles/
done
dangling=$(find "$HOME/.config/opencode" "$HOME/.claude/skills" -xtype l 2>/dev/null)
check "no dangling links in ~/.config/opencode, ~/.claude/skills" [ -z "$dangling" ]

# --- secrets and environment
# `systemctl show` reports Result=success even for units that don't exist,
# so require the unit to be loaded too.
check "sops-nix service loaded and succeeded" \
  [ "$(systemctl --user show -p LoadState -p Result sops-nix 2>/dev/null | sort | xargs)" = "LoadState=loaded Result=success" ]
# The secrets dir is itself a symlink into /run/user/<uid>/secrets.d: follow it.
n=$(find -L "$HOME/.config/sops-nix/secrets" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l)
check "4 secrets linked ($n)" [ "$n" -eq 4 ]
check "GITHUB_PERSONAL_ACCESS_TOKEN set" lz 'test -n "$GITHUB_PERSONAL_ACCESS_TOKEN"'
check "LD_LIBRARY_PATH unset" lz 'test -z "$LD_LIBRARY_PATH"'

# --- tools
check "uvx markitdown runs (numpy wheels load)" lz 'uvx --from markitdown markitdown --help >/dev/null 2>&1'
check "uv tool graphifyy installed" lz 'uv tool list | grep -q graphifyy'
check "ripwire 0.6.5" lz 'ripwire --version 2>&1 | grep -q 0.6.5'
check "orx runs" lz 'orx --help >/dev/null 2>&1'
check "nvim starts headless" lz "nvim --headless +qa 2>$T/nvim.err && test ! -s $T/nvim.err"
check "tmux loads continuum" lz 'tmux -L hmcheck new-session -d && tmux -L hmcheck show-options -g | grep -q @continuum-restore; r=$?; tmux -L hmcheck kill-server; exit $r'

# --- headless browser
lz "chromium --headless --no-sandbox --disable-gpu --window-size=800,600 --screenshot=$T/s.png 'data:text/html,<h1>Hello WSL</h1>' >/dev/null 2>&1"
check "chromium headless screenshot" [ -s "$T/s.png" ]
if lz 'whence -p fc-list >/dev/null'; then
  check "fontconfig sees Noto" lz 'fc-list | grep -qi noto'
else
  skip "fc-list not on PATH"
fi
check "agent-browser doctor" lz 'agent-browser doctor >/dev/null 2>&1'

if ((failures)); then
  echo "$failures live checks failed"
  exit 1
fi
echo "OK (live)"
