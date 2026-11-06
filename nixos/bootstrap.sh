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
Usage: bootstrap.sh [--dry-run] [--age-key FILE]
       bootstrap.sh --add-recipient AGE_PUBKEY

  (no flags)       init submodules, set up this machine's age key, check access
                   to secrets, dry-build, then install the system for next boot
  --dry-run        print every mutating command as "DRY-RUN: <cmd>" instead of
                   running it (read-only checks still run)
  --age-key FILE   import this existing age key instead of generating one
  --add-recipient AGE_PUBKEY
                   on a machine that can decrypt the secrets: add another
                   machine's public key and re-encrypt. Does not commit.
  --help           show this help
EOF
}

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
REPO=$(dirname "$SCRIPT_DIR")
FLAKE="$REPO/nixos"
SOPS_CONFIG="$REPO/.sops.yaml"
SECRETS_FILE="$FLAKE/secrets/secrets.yaml"
AGE_KEY_FILE="${AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"
MACHINE_DIR="${DOTFILES_MACHINE_DIR:-/etc/nixos}"
HTTPS_REWRITE='url.https://github.com/.insteadOf=git@github.com:'
DRY_RUN=0
IMPORT_KEY=""
ADD_RECIPIENT=""
PUBKEY=""

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
  SOPS_AGE_KEY_FILE="$AGE_KEY_FILE" with_tool sops sops --config "$SOPS_CONFIG" "$@"
}

# Append PUBKEY to the `age:` recipients in .sops.yaml, once.
register_recipient() {
  local pubkey=$1
  grep -qF -- "$pubkey" "$SOPS_CONFIG" && return 0
  grep -qE '^[[:space:]]*age:' "$SOPS_CONFIG" || fail "no 'age:' line in $SOPS_CONFIG"
  sed -i -E "s|^([[:space:]]*age:[[:space:]]*.*[^[:space:]])[[:space:]]*\$|\\1,$pubkey|" "$SOPS_CONFIG"
}

add_recipient() {
  [[ "$ADD_RECIPIENT" == age1* ]] || fail "not an age public key: $ADD_RECIPIENT"
  run register_recipient "$ADD_RECIPIENT"
  run sops_cmd updatekeys -y "$SECRETS_FILE"
  echo "Added. Commit .sops.yaml and nixos/secrets/secrets.yaml, then push."
  echo "On the other machine: git pull && update"
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

# An imported key is checked before it replaces anything.
import_age_key() {
  local source=$1
  [[ -f "$source" ]] || fail "age key not found: $source"
  with_tool age age-keygen -y "$source" >/dev/null 2>&1 || fail "not a valid age key: $source"
  run mkdir -p -m 700 "$(dirname "$AGE_KEY_FILE")"
  run install -m 600 "$source" "$AGE_KEY_FILE"
}

ensure_age_key() {
  if [[ -n "$IMPORT_KEY" ]]; then
    import_age_key "$IMPORT_KEY"
  elif [[ ! -f "$AGE_KEY_FILE" ]]; then
    local answer=""
    if [[ -t 0 ]] && ! ((DRY_RUN)); then
      read -r -p "Path to an existing age key (Enter to generate a new one): " answer
    fi
    if [[ -n "$answer" ]]; then
      import_age_key "$answer"
    else
      run mkdir -p -m 700 "$(dirname "$AGE_KEY_FILE")"
      run with_tool age age-keygen -o "$AGE_KEY_FILE"
      ((DRY_RUN)) || chmod 600 "$AGE_KEY_FILE"
    fi
  fi
  [[ -f "$AGE_KEY_FILE" ]] || return 0
  PUBKEY=$(with_tool age age-keygen -y "$AGE_KEY_FILE")
}

# A new machine's key can't decrypt until a trusted machine rekeys, so this
# warns instead of stopping: you still get your desktop, without the secrets.
check_secrets() {
  if ((DRY_RUN)) && [[ ! -f "$AGE_KEY_FILE" ]]; then
    echo "DRY-RUN: would check that this machine can decrypt $SECRETS_FILE"
    return 0
  fi
  if sops_cmd -d "$SECRETS_FILE" >/dev/null 2>&1; then
    return 0
  fi
  cat <<EOF

WARNING: this machine's age key cannot decrypt the secrets yet, so /run/secrets
will stay empty. To grant access, on a machine that can decrypt, run:

  bash ~/dotfiles/nixos/bootstrap.sh --add-recipient $PUBKEY

Commit and push there. Then here: git pull && update

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
      --age-key)
        [[ $# -ge 2 ]] || fail "--age-key needs a file"
        IMPORT_KEY=$2
        shift
        ;;
      --add-recipient)
        [[ $# -ge 2 ]] || fail "--add-recipient needs a public key"
        ADD_RECIPIENT=$2
        shift
        ;;
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

  if [[ -n "$ADD_RECIPIENT" ]]; then
    add_recipient
    exit 0
  fi

  check_preconditions
  ensure_submodule
  ensure_age_key
  check_secrets
  install_system

  ((DRY_RUN)) && exit 0
  echo
  echo "Done. Your system starts on the next boot."
  if [[ -t 0 ]]; then
    local answer=""
    read -r -p "Reboot now? [Y/n] " answer
    [[ "$answer" == [nN]* ]] || sudo systemctl reboot
  fi
}

main "$@"
