#!/usr/bin/env bash
# Tests lib/user.nix identity resolution.
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(dirname "$HERE")
USER_NIX="$ROOT/lib/user.nix"
NIX=$(command -v nix) || { echo "nix not found in PATH" >&2; exit 2; }
[[ -f "$USER_NIX" ]] || { echo "missing $USER_NIX" >&2; exit 2; }
failures=0
count=0

check() {
  local desc=$1 field=$2 want=$3
  shift 3
  count=$((count + 1))
  local got
  got=$(env "$@" "$NIX" eval --impure --raw --file "$USER_NIX" --apply "u: u.$field")
  [[ "$got" == "$want" ]] || { echo "FAIL $desc: got '$got' want '$want'"; failures=$((failures + 1)); }
}

check_pure() {
  local desc=$1 field=$2 want=$3
  count=$((count + 1))
  local got
  # --pure-eval forbids importing paths outside the flake source, so isolate the
  # environment instead; getEnv then returns "" exactly as it does in pure eval.
  got=$(env -i "$NIX" eval --impure --raw --file "$USER_NIX" --apply "u: u.$field")
  [[ "$got" == "$want" ]] || { echo "FAIL $desc: got '$got' want '$want'"; failures=$((failures + 1)); }
}

check_pure "pure user" username asergi
check_pure "pure home" homeDirectory /home/asergi
check "user" username alice -u SUDO_USER USER=alice HOME=/home/alice
check "home" homeDirectory /home/alice -u SUDO_USER USER=alice HOME=/home/alice
check "custom home" homeDirectory /tmp/alice -u SUDO_USER USER=alice HOME=/tmp/alice
check "dotted user" username andrea.sergi -u SUDO_USER USER=andrea.sergi HOME=/home/andrea.sergi
check "sudo user wins" username alice SUDO_USER=alice USER=root HOME=/root
check "sudo home" homeDirectory /home/alice SUDO_USER=alice USER=root HOME=/root
check "root stays root" homeDirectory /root -u SUDO_USER USER=root HOME=/root
check "root user" username root -u SUDO_USER USER=root HOME=/root
check "sudo from root falls through" username alice SUDO_USER=root USER=alice HOME=/home/alice
check "sudo from root home" homeDirectory /home/alice SUDO_USER=root USER=alice HOME=/home/alice
check "root dotfiles" dotfiles /root/dotfiles -u SUDO_USER USER=root HOME=/root
check "dotfiles" dotfiles /tmp/alice/dotfiles -u SUDO_USER USER=alice HOME=/tmp/alice
check "override user" username alice -u SUDO_USER DOTFILES_USER=alice USER=root HOME=/root
check "override user wins over sudo" username alice -u SUDO_USER DOTFILES_USER=alice SUDO_USER=root USER=root HOME=/root
check "override home" homeDirectory /data/alice -u SUDO_USER DOTFILES_HOME=/data/alice USER=alice HOME=/home/alice
check "override home under sudo" homeDirectory /data/alice -u SUDO_USER DOTFILES_HOME=/data/alice SUDO_USER=alice USER=root HOME=/root
check "override dotfiles" dotfiles /data/alice/dotfiles -u SUDO_USER DOTFILES_HOME=/data/alice USER=alice HOME=/home/alice

if ((failures)); then
  echo "$failures of $count user tests failed"
  exit 1
fi
echo "OK ($count user tests)"
