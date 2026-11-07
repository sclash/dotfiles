#!/usr/bin/env bash
# Bring an installed NixOS machine up to the ~/dotfiles/nixos flake.
# Sets up the personal layer only: the machine layer (disks, bootloader,
# hostname, ...) stays in /etc/nixos. Safe to re-run.
#
# Exit codes: 0 done, 1 precondition failed, 2 action needed from you
# (the exact next command is printed).
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: bootstrap.sh [--dry-run]

  (no flags)  init submodules, check this machine's secrets, dry-build, then
              install the system for next boot
  --dry-run   print every mutating command as "DRY-RUN: <cmd>" instead of
              running it (read-only checks still run)
  --help      show this help
EOF
}

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
REPO=$(dirname "$SCRIPT_DIR")
FLAKE="$REPO/nixos"
SECRETS_FILE="$HOME/.config/sops/secrets.yaml"
AGE_KEY_FILE="${AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"
MACHINE_DIR="${DOTFILES_MACHINE_DIR:-/etc/nixos}"
HTTPS_REWRITE='url.https://github.com/.insteadOf=git@github.com:'
DRY_RUN=0

run() {
  if ((DRY_RUN)); then
    echo "DRY-RUN: $*"
  else
    "$@"
  fi
}

fail() {
  echo "bootstrap: $*" >&2
  exit 1
}

action_needed() {
  echo
  echo "ACTION NEEDED: $*"
  exit 2
}

# Tools come from the flake's own lock, so they match the system's versions.
with_tool() {
  local tool=$1
  shift
  nix shell --inputs-from "$FLAKE" "nixpkgs#$tool" -c "$@"
}

sops_cmd() {
  SOPS_AGE_KEY_FILE="$AGE_KEY_FILE" with_tool sops sops "$@"
}

check_preconditions() {
  ((EUID != 0)) || fail "run this as your normal user, not root"
  [[ -n "${USER:-}" && -n "${HOME:-}" ]] || fail "USER and HOME must be set"
  command -v nix >/dev/null || fail "nix is not on PATH"
  command -v git >/dev/null || fail "git is not on PATH"

  # Config symlinks such as ~/.config/hypr point into ~/dotfiles.
  local expected
  expected=$(cd "$HOME/dotfiles" 2>/dev/null && pwd -P) || expected=""
  [[ "$REPO" == "$expected" ]] || fail "this repo must be at ~/dotfiles (it is at $REPO)"

  local file
  for file in hardware-configuration.nix machine.nix; do
    [[ -f "$MACHINE_DIR/$file" ]] || action_needed "$MACHINE_DIR/$file is missing.
This flake reads the machine layer from there. The installer creates it; on an
existing machine, create it by hand with the hostname, timezone, bootloader and
stateVersion, then re-run."
  done
}

ensure_submodule() {
  [[ "$(git -C "$REPO" submodule status neovimrc 2>/dev/null)" == -* ]] || return 0
  run git -C "$REPO" -c "$HTTPS_REWRITE" submodule update --init neovimrc
}

# The installer creates this machine's age key and secrets file. If they're
# missing this warns instead of stopping: you still get your desktop, without
# the secrets.
check_secrets() {
  if [[ -f "$SECRETS_FILE" ]] && sops_cmd -d "$SECRETS_FILE" >/dev/null 2>&1; then
    return 0
  fi
  cat <<EOF

WARNING: this machine can't read $SECRETS_FILE
with the age key $AGE_KEY_FILE, so /run/secrets will stay empty.
The installer normally creates both. To create them by hand, see SOPS-README.md.

EOF
}

install_system() {
  local target="$FLAKE#default"
  # A dry build is the real compatibility check, including on an unsupported
  # architecture. It fails here, before anything changes.
  nixos-rebuild dry-build --flake "$target" --impure ||
    fail "this flake does not build on this machine; nothing was changed"
  run sudo env SUDO_USER="$USER" DOTFILES_HOME="$HOME" \
    nixos-rebuild boot --flake "$target" --impure
}

main() {
  while (($#)); do
    case "$1" in
      --dry-run) DRY_RUN=1 ;;
      --help)
        usage
        exit 0
        ;;
      *)
        usage >&2
        exit 1
        ;;
    esac
    shift
  done

  check_preconditions
  ensure_submodule
  check_secrets
  install_system

  ((DRY_RUN)) && exit 0
  cat <<'EOF'

Done. Your system starts on the next boot.

After that, enter this machine's credentials:

  sops edit ~/.config/sops/secrets.yaml
  update

EOF
  if [[ -t 0 ]]; then
    local answer=""
    read -r -p "Reboot now? [Y/n] " answer
    [[ "$answer" == [nN]* ]] || sudo systemctl reboot
  fi
}

main "$@"
