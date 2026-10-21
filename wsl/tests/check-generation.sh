#!/usr/bin/env bash
# Assertions on a built home-manager generation (the activation package).
# Usage: check-generation.sh GEN
# Runs inside the flake check sandbox: only store paths are readable, so
# out-of-store links are checked by their target path, never resolved.
set -uo pipefail

GEN=${1:?usage: check-generation.sh GEN}
failures=0
count=0

fail() {
  echo "FAIL: $*"
  failures=$((failures + 1))
}

check() {
  count=$((count + 1))
  "$@"
}

has_bin() {
  for b in "$@"; do
    check test -e "$GEN/home-path/bin/$b" || fail "has_bin $b"
  done
}

lacks_bin() {
  for b in "$@"; do
    check test ! -e "$GEN/home-path/bin/$b" || fail "lacks_bin $b"
  done
}

has_path() {
  check test -e "$GEN/$1" || fail "has_path $1"
}

lacks_path() {
  check test ! -e "$GEN/$1" -a ! -L "$GEN/$1" || fail "lacks_path $1"
}

is_dir() {
  local p="$GEN/home-files/$1"
  check test -d "$p" -a ! -L "$p" || fail "is_dir $1"
}

# Follow the symlink chain while it stays inside /nix/store; the first
# target outside the store is where the out-of-store link points.
links_to() {
  local rel=$1 want=$2 p="$GEN/home-files/$1" hops=0
  count=$((count + 1))
  while [[ -L "$p" && $hops -lt 10 ]]; do
    p=$(readlink "$p")
    [[ "$p" == /nix/store/* ]] || break
    hops=$((hops + 1))
  done
  [[ "$p" == "$want" ]] || fail "links_to $rel $want (got $p)"
}

contains() {
  check grep -qF -- "$2" "$GEN/$1" || fail "contains $1 $2"
}

lacks() {
  count=$((count + 1))
  if grep -qF -- "$2" "$GEN/$1"; then fail "lacks $1 $2"; fi
}

run_contains() {
  local want=$1 bin=$2
  shift 2
  check grep -qF -- "$want" <("$GEN/home-path/bin/$bin" "$@" 2>&1) || fail "run_contains $want $bin $*"
}

# --- Task 1: base
has_bin home-manager
V=home-path/etc/profile.d/hm-session-vars.sh
contains $V 'export EDITOR="nvim"'
contains $V 'export VISUAL="nvim"'
contains $V 'export SUDO_EDITOR="nvim"'
contains $V '.opencode/bin'
contains $V '.local/bin'
contains $V 'LANG="en_US.UTF-8"'
contains $V 'XDG_DATA_DIRS'
lacks $V 'LD_LIBRARY_PATH'
contains home-files/.config/git/config 'name = "sclash"'

# --- Task 2: program modules + links
has_bin tmux starship atuin nu uv devenv pandoc xelatex ripwire herdr \
  vtsls pyright clangd gopls zls lua-language-server texlab rust-analyzer \
  codelldb debugpy-adapter prettier black dlv
run_contains 0.6.5 ripwire --version
contains home-files/.config/tmux/tmux.conf sessionx
contains home-files/.config/tmux/tmux.conf continuum-restore
links_to .config/nvim /home/asergi/dotfiles/neovimrc
links_to .config/starship /home/asergi/dotfiles/starship
links_to .config/atuin /home/asergi/dotfiles/atuin
links_to .config/uv/uv.toml /home/asergi/dotfiles/wsl/uv/uv.toml
is_dir .config/herdr
links_to .config/herdr/config.toml /home/asergi/dotfiles/herdr/config.toml
# Build limits for the 3.6 GiB WSL VM: one derivation at a time, two compile
# threads. nix.package only validates nix.conf; it must not shadow Determinate's nix.
contains home-files/.config/nix/nix.conf 'max-jobs = 1'
contains home-files/.config/nix/nix.conf 'cores = 2'
lacks_bin nix

if [[ $failures -gt 0 ]]; then
  echo "$failures of $count assertions failed"
  exit 1
fi
echo "OK ($count assertions)"
