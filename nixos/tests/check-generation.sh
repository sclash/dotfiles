#!/usr/bin/env bash
# Assertions on a built NixOS home-manager generation.
# Usage: check-generation.sh GEN HOMEDIR SOPS_KEY OPENCODE_SRC
set -uo pipefail

GEN=${1:?usage: check-generation.sh GEN HOMEDIR SOPS_KEY OPENCODE_SRC}
HOMEDIR=${2:?usage: check-generation.sh GEN HOMEDIR SOPS_KEY OPENCODE_SRC}
SOPS_KEY=${3:?usage: check-generation.sh GEN HOMEDIR SOPS_KEY OPENCODE_SRC}
SOURCE=${4:?usage: check-generation.sh GEN HOMEDIR SOPS_KEY OPENCODE_SRC}
failures=0
count=0

has() {
  count=$((count + 1))
  grep -qF -- "$2" "$GEN/$1" || { echo "FAIL: $1 lacks $2"; failures=$((failures + 1)); }
}

lacks() {
  count=$((count + 1))
  if [[ ! -r "$GEN/$1" ]]; then
    echo "FAIL: $1 is missing or unreadable"
    failures=$((failures + 1))
    return
  fi
  grep -qF -- "$2" "$GEN/$1" && { echo "FAIL: $1 has $2"; failures=$((failures + 1)); }
}

has_file() {
  count=$((count + 1))
  grep -qF -- "$1" "$SOURCE" || { echo "FAIL: opencode source lacks $1"; failures=$((failures + 1)); }
}

lacks_file() {
  count=$((count + 1))
  grep -qF -- "$1" "$SOURCE" && { echo "FAIL: opencode source has $1"; failures=$((failures + 1)); }
}

link_target() {
  local p=$1 hops=0
  while [[ -L "$p" && $hops -lt 10 ]]; do
    p=$(readlink "$p")
    [[ "$p" == /nix/store/* ]] || break
    hops=$((hops + 1))
  done
  printf '%s\n' "$p"
}

Z=home-files/.zshrc
has "$Z" 'sudo env SUDO_USER="$USER" DOTFILES_HOME="$HOME" nixos-rebuild switch --flake $HOME/dotfiles/nixos#nixos-os --impure'
has "$Z" "$HOMEDIR/dotfiles/scripts/tmux-sessionizer.sh"
if [[ "$HOMEDIR" != /home/asergi ]]; then
  lacks "$Z" /home/asergi
fi

has_file "/run/secrets"
has_file "{env:HOME}"
lacks_file "/home/asergi"

J=home-files/.config/opencode/opencode.jsonc
count=$((count + 1))
[[ "$(link_target "$GEN/$J")" == "$HOMEDIR/dotfiles/my-opencode/v2/opencode.jsonc" ]] \
  || { echo "FAIL: opencode.jsonc does not link to v2"; failures=$((failures + 1)); }

R=home-files/.config/opencode/RIPWIRE.md
count=$((count + 1))
[[ "$(link_target "$GEN/$R")" == "$HOMEDIR/dotfiles/my-opencode/v2/RIPWIRE.md" ]] \
  || { echo "FAIL: RIPWIRE.md does not link to v2"; failures=$((failures + 1)); }

A=home-files/.config/atuin
count=$((count + 1))
[[ "$(link_target "$GEN/$A")" == "$HOMEDIR/dotfiles/atuin" ]] \
  || { echo "FAIL: atuin does not link to repo"; failures=$((failures + 1)); }

count=$((count + 1))
[[ "$SOPS_KEY" == "$HOMEDIR/.config/sops/age/keys.txt" ]] \
  || { echo "FAIL: sops key path $SOPS_KEY"; failures=$((failures + 1)); }

count=$((count + 1))
smoke_home=$(mktemp -d)
HOME="$smoke_home" "$GEN/home-path/bin/opencode" --version >/dev/null 2>&1 \
  || { echo "FAIL: opencode --version"; failures=$((failures + 1)); }
rm -rf "$smoke_home"

# The pure-eval fallback legitimately targets /home/asergi.
if [[ "$HOMEDIR" != /home/asergi ]] && grep -rqF /home/asergi "$GEN"; then
  echo "FAIL: generation contains /home/asergi"
  failures=$((failures + 1))
fi

if ((failures)); then
  echo "$failures of $count nixos generation checks failed"
  exit 1
fi
echo "OK ($count nixos generation checks)"
