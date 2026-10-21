#!/usr/bin/env bash
# Bring an Ubuntu WSL instance up to the ~/dotfiles/wsl home-manager flake.
# Idempotent: every step checks before acting, so re-running is safe.
#
# Exit codes: 0 done, 1 precondition failed, 2 action needed from you
# (the exact next command is printed).

usage() {
  cat <<'EOF'
Usage: bootstrap.sh [--dry-run] [--cleanup]
       bootstrap.sh --add-recipient AGE_PUBKEY

  (no flags)       enable systemd, install zsh/locale/Nix, init submodules,
                   generate this instance's age key, check secrets access,
                   then home-manager switch
  --dry-run        print every mutating command as "DRY-RUN: <cmd>" instead of
                   running it (read-only checks still run)
  --cleanup        after the switch, remove the pre-Nix installs (snaps,
                   rustup, nvm, oh-my-zsh, p10k, ~/.local/bin/herdr, ...);
                   lists them and asks first
  --add-recipient AGE_PUBKEY
                   on an instance that can decrypt wsl/secrets/secrets.yaml:
                   add another instance's public key and re-encrypt
  --help           show this help
EOF
}

EXPECTED_REPO=/home/asergi/dotfiles
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || dirname "$SCRIPT_DIR")
FLAKE="$REPO/wsl"
AGE_KEY_FILE=${AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}
SOPS_CONFIG=${SOPS_CONFIG:-$FLAKE/.sops.yaml}
SECRETS_FILE=${SECRETS_FILE:-$FLAKE/secrets/secrets.yaml}
SECRET_KEYS=(github_pat openrouter opencode cheaper_inference)
DRY_RUN=0

run() {
  if ((DRY_RUN)); then
    echo "DRY-RUN: $*"
  else
    "$@"
  fi
}

action_needed() {
  echo
  echo "ACTION NEEDED: $*"
  exit 2
}

sops_cmd() {
  SOPS_AGE_KEY_FILE="$AGE_KEY_FILE" nix run "$FLAKE#sops" -- "$@"
}

public_key() {
  nix shell "$FLAKE#age" -c age-keygen -y "$AGE_KEY_FILE" 2>/dev/null
}

# Append PUBKEY to the single-line `age:` recipients in SOPS_YAML, once.
register_recipient() {
  local pubkey=$1 config=$2
  grep -qF -- "$pubkey" "$config" && return 0
  grep -qE '^[[:space:]]*age:' "$config" || {
    echo "bootstrap: no 'age:' line in $config" >&2
    return 1
  }
  sed -i -E "s|^([[:space:]]*age:[[:space:]]*.*[^[:space:]])[[:space:]]*\$|\\1,$pubkey|" "$config"
}

# Print ok | missing | undecryptable | missing-keys:<a,b>. Read-only.
secrets_status() {
  local config=$1 file=$2 plain key
  local -a absent=()
  [[ -f "$file" ]] || {
    echo missing
    return 0
  }
  plain=$(sops_cmd --config "$config" -d "$file" 2>/dev/null) || {
    echo undecryptable
    return 0
  }
  for key in "${SECRET_KEYS[@]}"; do
    grep -qE "^${key}:" <<<"$plain" || absent+=("$key")
  done
  if ((${#absent[@]})); then
    (
      IFS=,
      echo "missing-keys:${absent[*]}"
    )
  else
    echo ok
  fi
}

check_location() {
  if [[ "$HOME" != /home/asergi || "$REPO" != "$HOME/dotfiles" ]]; then
    echo "bootstrap: this flake expects the repo at $EXPECTED_REPO and user asergi" \
      "(HOME=$HOME, repo=$REPO)" >&2
    exit 1
  fi
}

ensure_systemd() {
  grep -qE '^[[:space:]]*systemd[[:space:]]*=[[:space:]]*true' /etc/wsl.conf 2>/dev/null && return 0
  run sudo sh -c 'printf "[boot]\nsystemd=true\n" >> /etc/wsl.conf'
  action_needed "systemd enabled in /etc/wsl.conf. From Windows run: wsl.exe --shutdown, then re-run this script."
}

ensure_shell_and_locale() {
  local pkg shell
  local -a apt=()
  for pkg in zsh git curl; do
    dpkg -s "$pkg" >/dev/null 2>&1 || apt+=("$pkg")
  done
  if ((${#apt[@]})); then
    run sudo apt-get update
    run sudo apt-get install -y "${apt[@]}"
  fi
  shell=$(getent passwd "$(id -un)" | cut -d: -f7)
  [[ "$shell" == /usr/bin/zsh ]] || run chsh -s /usr/bin/zsh
  locale -a 2>/dev/null | grep -qix 'en_US.utf8' || run sudo locale-gen en_US.UTF-8
}

ensure_nix() {
  command -v nix >/dev/null 2>&1 && return 0
  run sh -c 'curl -fsSL https://install.determinate.systems/nix | sh -s -- install --no-confirm'
  local profile=/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
  # shellcheck source=/dev/null
  [[ -e "$profile" ]] && . "$profile"
  command -v nix >/dev/null 2>&1 || ((DRY_RUN)) || action_needed "Nix is not on PATH yet. Open a new shell and re-run."
}

ensure_submodules() {
  [[ "$(git -C "$REPO" submodule status neovimrc 2>/dev/null)" == -* ]] || return 0
  run git -C "$REPO" submodule update --init neovimrc
}

# Generate this instance's age key (never copied between instances) and
# register its public key as a sops recipient.
ensure_age_key() {
  if [[ ! -f "$AGE_KEY_FILE" ]]; then
    run mkdir -p -m 700 "$(dirname "$AGE_KEY_FILE")"
    run nix shell "$FLAKE#age" -c age-keygen -o "$AGE_KEY_FILE"
    ((DRY_RUN)) || chmod 600 "$AGE_KEY_FILE"
  fi
  [[ -f "$AGE_KEY_FILE" ]] || return 0
  PUBKEY=$(public_key)
  grep -qF -- "$PUBKEY" "$SOPS_CONFIG" || run register_recipient "$PUBKEY" "$SOPS_CONFIG"
}

check_secrets() {
  local status pub=${PUBKEY:-<this instance\'s age public key>}
  status=$(secrets_status "$SOPS_CONFIG" "$SECRETS_FILE")
  case "$status" in
    ok) ;;
    missing)
      action_needed "no secrets file yet. Create it (keys: ${SECRET_KEYS[*]}):
  cd $FLAKE && nix run .#sops -- --config $SOPS_CONFIG $SECRETS_FILE
then git add it and re-run."
      ;;
    undecryptable)
      action_needed "this instance's key cannot decrypt $SECRETS_FILE.
On an instance that can, run:
  bash ~/dotfiles/wsl/bootstrap.sh --add-recipient $pub
commit wsl/.sops.yaml and wsl/secrets/secrets.yaml, bring that commit here, and re-run.
(Or re-create the file with this key only, which drops the other instances' access.)"
      ;;
    missing-keys:*)
      action_needed "$SECRETS_FILE lacks: ${status#missing-keys:}. Add them:
  nix run $FLAKE#sops -- --config $SOPS_CONFIG $SECRETS_FILE"
      ;;
  esac
}

switch() {
  local -a args=(switch --flake "$FLAKE#asergi" -b hm-backup --max-jobs 1 --cores 2)
  if command -v home-manager >/dev/null 2>&1; then
    run home-manager "${args[@]}"
  else
    run nix run "$FLAKE#home-manager" -- "${args[@]}"
  fi
}

add_recipient() {
  local pubkey=$1
  [[ "$pubkey" =~ ^age1[0-9a-z]+$ ]] || {
    echo "bootstrap: not an age public key: $pubkey" >&2
    exit 1
  }
  [[ "$(secrets_status "$SOPS_CONFIG" "$SECRETS_FILE")" == ok ]] || {
    echo "bootstrap: this instance cannot decrypt $SECRETS_FILE; run --add-recipient where it can" >&2
    exit 1
  }
  run register_recipient "$pubkey" "$SOPS_CONFIG"
  run sops_cmd --config "$SOPS_CONFIG" updatekeys -y "$SECRETS_FILE"
  echo "Added $pubkey. Commit $SOPS_CONFIG and $SECRETS_FILE."
}

# shellcheck disable=SC2088 # "~/..." strings are display names; commands use $HOME
cleanup() {
  local -a names=() cmds=()
  local s
  item() {
    names+=("$1")
    cmds+=("$2")
  }
  for s in nvim go zig node pyright universal-ctags; do
    snap list "$s" >/dev/null 2>&1 && item "snap $s" "sudo snap remove $s"
  done
  [[ -x "$HOME/.cargo/bin/rustup" ]] && item "rustup (~/.cargo, ~/.rustup)" "$HOME/.cargo/bin/rustup self uninstall -y"
  grep -qs '\.cargo/env' "$HOME/.profile" "$HOME/.bashrc" \
    && item ".cargo/env lines in ~/.profile, ~/.bashrc" "sed -i /\\.cargo\\/env/d $HOME/.profile $HOME/.bashrc"
  [[ -e "$HOME/.nvm" ]] && item "~/.nvm" "rm -rf $HOME/.nvm"
  [[ -e "$HOME/.oh-my-zsh" ]] && item "~/.oh-my-zsh" "rm -rf $HOME/.oh-my-zsh"
  [[ -e "$HOME/.p10k.zsh" ]] && item "~/.p10k.zsh" "rm -f $HOME/.p10k.zsh"
  [[ -e "$HOME/.local/bin/herdr" ]] && item "~/.local/bin/herdr" "rm -f $HOME/.local/bin/herdr"
  [[ -e /usr/local/lib/node_modules/pyright ]] \
    && item "npm-global pyright (/usr/local)" "sudo rm -rf /usr/local/lib/node_modules/pyright /usr/local/bin/pyright"
  [[ -e "$HOME/.tmux/plugins" ]] && item "~/.tmux/plugins (old TPM)" "rm -rf $HOME/.tmux/plugins"
  [[ -e "$HOME/.config/tmux/plugins" ]] && item "~/.config/tmux/plugins (old TPM)" "rm -rf $HOME/.config/tmux/plugins"

  if ((${#names[@]} == 0)); then
    echo "Cleanup: nothing to remove."
    return 0
  fi
  echo "Cleanup will remove:"
  printf '  - %s\n' "${names[@]}"
  if ((!DRY_RUN)); then
    local answer
    read -r -p "Remove these? [y/N] " answer
    [[ "$answer" == [yY]* ]] || {
      echo "Nothing removed."
      return 0
    }
  fi
  local c
  for c in "${cmds[@]}"; do
    # shellcheck disable=SC2086 # each command is a plain word list
    run $c
  done
}

main() {
  local do_cleanup=0 recipient=""
  while (($#)); do
    case "$1" in
      --dry-run) DRY_RUN=1 ;;
      --cleanup) do_cleanup=1 ;;
      --add-recipient)
        recipient=${2:-}
        [[ -n "$recipient" ]] || {
          usage >&2
          exit 1
        }
        shift
        ;;
      --help | -h)
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

  check_location
  if [[ -n "$recipient" ]]; then
    add_recipient "$recipient"
    return 0
  fi

  ensure_systemd
  ensure_shell_and_locale
  ensure_nix
  ensure_submodules
  ensure_age_key
  check_secrets
  switch
  ((do_cleanup)) && cleanup
  return 0
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -euo pipefail
  main "$@"
fi
