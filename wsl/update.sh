#!/usr/bin/env bash
set -euo pipefail
local_secrets=$HOME/.config/sops-nix/wsl-secrets.yaml
if [[ -z "${DOTFILES_WSL_SECRETS:-}" && -f "$local_secrets" ]]; then
  export DOTFILES_WSL_SECRETS="$local_secrets"
fi
if [[ -n "${DOTFILES_WSL_SECRETS:-}" ]]; then
  if [[ "$DOTFILES_WSL_SECRETS" != /* ]]; then
    echo "update: DOTFILES_WSL_SECRETS must be an absolute path: $DOTFILES_WSL_SECRETS" >&2
    exit 1
  fi
  if [[ ! -e "$DOTFILES_WSL_SECRETS" ]]; then
    echo "update: DOTFILES_WSL_SECRETS does not exist: $DOTFILES_WSL_SECRETS" >&2
    exit 1
  fi
fi

flake=$HOME/dotfiles/wsl
if [[ -n "${DOTFILES_WSL_SECRETS:-}" ]]; then
  SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}" \
    nix run "$flake#sops" -- --config "$flake/.sops.yaml" \
      --filename-override secrets/secrets.yaml -d "$DOTFILES_WSL_SECRETS" >/dev/null || {
        echo "update: cannot decrypt DOTFILES_WSL_SECRETS: $DOTFILES_WSL_SECRETS" >&2
        exit 1
      }
fi
want_user=$(id -un)
want_home=${HOME%/}
got_user=$(nix eval --raw --impure --no-write-lock-file "$flake#homeConfigurations.default.config.home.username") || {
  echo "update: cannot evaluate the flake identity (see error above)" >&2
  exit 1
}
got_home=$(nix eval --raw --impure --no-write-lock-file "$flake#homeConfigurations.default.config.home.homeDirectory") || {
  echo "update: cannot evaluate the flake identity (see error above)" >&2
  exit 1
}
if [[ "$got_user" != "$want_user" || "${got_home%/}" != "$want_home" ]]; then
  echo "update: flake resolves to ($got_user, $got_home) but this account is ($want_user, $want_home)." >&2
  echo "update: run as the WSL login user; unset stale SUDO_USER or USER overrides." >&2
  exit 1
fi

args=(switch --flake "$flake#default" -b hm-backup --impure --max-jobs 1 --cores 2)
if command -v home-manager >/dev/null 2>&1; then
  exec home-manager "${args[@]}"
else
  exec nix run "$HOME/dotfiles/wsl#home-manager" -- "${args[@]}"
fi
