#!/usr/bin/env bash
# Bring a Linux WSL instance up to the ~/dotfiles/wsl home-manager flake.
# Idempotent: every step checks before acting, so re-running is safe.
#
# Exit codes: 0 done, 1 precondition failed, 2 action needed from you
# (the exact next command is printed).

usage() {
  cat <<'EOF'
Usage: bootstrap.sh [--dry-run] [--cleanup] [--new-secrets]
       bootstrap.sh --add-recipient AGE_PUBKEY

  (no flags)       enable systemd, install zsh/locale/Nix, init submodules,
                   generate this instance's age key, check secrets access,
                   then home-manager switch
  --dry-run        print every mutating command as "DRY-RUN: <cmd>" instead of
                   running it (read-only checks still run)
  --cleanup        after the switch, remove the pre-Nix installs (snaps,
                   rustup, nvm, oh-my-zsh, p10k, ~/.local/bin/herdr, ...);
                   lists them and asks first
  --new-secrets    create a local encrypted file at
                   ~/.config/sops-nix/wsl-secrets.yaml with empty values,
                   encrypted to this instance's age key, and continue the
                   switch; fill the values later (used when the shared secrets
                   file cannot be decrypted)
  --add-recipient AGE_PUBKEY
                   on an instance that can decrypt wsl/secrets/secrets.yaml:
                   add another instance's public key and re-encrypt
  --help           show this help
EOF
}

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || dirname "$SCRIPT_DIR")
FLAKE="$REPO/wsl"
AGE_KEY_FILE=${AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}
SOPS_CONFIG=${SOPS_CONFIG:-$FLAKE/.sops.yaml}
SECRETS_FILE=${SECRETS_FILE:-$FLAKE/secrets/secrets.yaml}
LOCAL_SECRETS=${LOCAL_SECRETS:-$HOME/.config/sops-nix/wsl-secrets.yaml}
ACTIVE_SECRETS=""
DO_NEW_SECRETS=0
SECRET_KEYS=(github_pat openrouter opencode cheaper_inference)
DRY_RUN=${DRY_RUN:-0}
LOCALE_GEN=${LOCALE_GEN:-/etc/locale.gen}

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

# Print ok | missing | undecryptable | missing-keys:<a,b> | empty-keys:<a,b>.
# Read-only.
secrets_status() {
  local config=$1 file=$2 plain key value
  local -a missing=() empty=()
  [[ -f "$file" ]] || {
    echo missing
    return 0
  }
  plain=$(sops_cmd --config "$config" --filename-override secrets/secrets.yaml -d "$file" 2>/dev/null) || {
    echo undecryptable
    return 0
  }
  for key in "${SECRET_KEYS[@]}"; do
    if ! grep -qE "^${key}:" <<<"$plain"; then
      missing+=("$key")
      continue
    fi
    value=$(sed -n "s/^${key}:[[:space:]]*//p" <<<"$plain")
    value=${value%$'\r'}
    case "$value" in
      "" | "null" | '""' | "''") empty+=("$key") ;;
    esac
  done
  if ((${#missing[@]})); then
    (
      IFS=,
      echo "missing-keys:${missing[*]}"
    )
  elif ((${#empty[@]})); then
    (
      IFS=,
      echo "empty-keys:${empty[*]}"
    )
  else
    echo ok
  fi
}

# Pick the secrets file this run should use: an explicit override, this
# instance's local file if it exists, otherwise the shared committed file.
resolve_secrets() {
  if [[ -n "${DOTFILES_WSL_SECRETS:-}" ]]; then
    ACTIVE_SECRETS=$DOTFILES_WSL_SECRETS
  elif [[ -f "$LOCAL_SECRETS" ]]; then
    ACTIVE_SECRETS=$LOCAL_SECRETS
  else
    ACTIVE_SECRETS=$SECRETS_FILE
  fi
}

# Create a local, encrypted secrets file with the required keys and empty
# values. The switch continues; the user fills the values later.
new_secrets() {
  local target=${DOTFILES_WSL_SECRETS:-$LOCAL_SECRETS}
  [[ "$target" == /* ]] || action_needed "DOTFILES_WSL_SECRETS must be an absolute path"
  if [[ -e "$target" || -L "$target" ]]; then
    echo "bootstrap: using existing local secrets $target"
    ACTIVE_SECRETS=$target
    return 0
  fi
  [[ -n "${PUBKEY:-}" ]] || action_needed "age public key is not available; re-run without --dry-run."
  [[ -f "$SOPS_CONFIG" ]] || action_needed "missing sops config: $SOPS_CONFIG"
  local dir template tmp
  dir=$(dirname "$target")
  if ((DRY_RUN)); then
    run mkdir -p -m 700 "$dir"
    echo "DRY-RUN: env SOPS_AGE_KEY_FILE=$AGE_KEY_FILE nix run $FLAKE#sops -- --config $SOPS_CONFIG --encrypt --age $PUBKEY --filename-override secrets/secrets.yaml --input-type yaml --output-type yaml <template> > $target"
    return 0
  fi
  template=$(mktemp) || action_needed "could not create a temporary file"
  chmod 600 "$template"
  printf '%s: ""\n' "${SECRET_KEYS[@]}" > "$template"
  run mkdir -p -m 700 "$dir" || {
    rm -f "$template"
    action_needed "could not create $dir"
  }
  umask 077
  tmp=$(mktemp "$dir/.wsl-secrets.XXXXXX") || {
    rm -f "$template"
    action_needed "could not create a temporary file in $dir"
  }
  if ! SOPS_AGE_KEY_FILE="$AGE_KEY_FILE" nix run "$FLAKE#sops" -- \
    --config "$SOPS_CONFIG" --encrypt --age "$PUBKEY" \
    --filename-override secrets/secrets.yaml --input-type yaml --output-type yaml "$template" > "$tmp"; then
    rm -f "$template" "$tmp"
    action_needed "sops encryption failed; check $SOPS_CONFIG and the age key"
  fi
  if ! SOPS_AGE_KEY_FILE="$AGE_KEY_FILE" nix run "$FLAKE#sops" -- \
    --config "$SOPS_CONFIG" --filename-override secrets/secrets.yaml -d "$tmp" >/dev/null; then
    rm -f "$template" "$tmp"
    action_needed "sops could not decrypt the new file; check AGE_KEY_FILE and PUBKEY"
  fi
  chmod 600 "$tmp"
  mv -f "$tmp" "$target" || {
    rm -f "$template" "$tmp"
    action_needed "could not move the new secrets file into place"
  }
  rm -f "$template"
  ACTIVE_SECRETS=$target
  echo "bootstrap: created $target with empty values; continuing."
  echo "bootstrap: fill them later through sops:"
  echo "  EDITOR=vi SOPS_AGE_KEY_FILE=$AGE_KEY_FILE nix run $FLAKE#sops -- --config $SOPS_CONFIG --filename-override secrets/secrets.yaml $target"
  echo "bootstrap: sops opens \$EDITOR; do not edit the encrypted file directly."
}

check_location() {
  if [[ -z "${HOME:-}" ]]; then
    echo "bootstrap: HOME must be set; run from the WSL login shell" >&2
    exit 1
  fi
  local expected="${HOME%/}/dotfiles"
  if [[ "$REPO" != "$expected" ]]; then
    echo "bootstrap: this flake expects the repo at $expected (repo=$REPO)" >&2
    exit 1
  fi
}

# WSL has an existing OS user that cannot be renamed: inherit it and never
# touch the account.
check_not_root() {
  if ((EUID == 0)); then
    echo "bootstrap: run as the existing WSL user, not root or sudo" >&2
    exit 1
  fi
  if [[ -z "${USER:-}" || -z "${HOME:-}" ]]; then
    echo "bootstrap: USER and HOME must be set; run from the WSL login shell" >&2
    exit 1
  fi
}

# Fail before switching if an impure evaluation does not match this account.
check_identity() {
  local want_user want_home got_user got_home
  if ! command -v nix >/dev/null 2>&1; then
    if ((DRY_RUN)); then
      echo "DRY-RUN: skip identity check (nix not installed)"
      return 0
    fi
    action_needed "Nix is not on PATH yet. Open a new shell and re-run."
  fi
  want_user=$(id -un)
  want_home=${HOME%/}
  got_user=$(nix eval --raw --impure --no-write-lock-file "$FLAKE#homeConfigurations.default.config.home.username") || {
    echo "bootstrap: cannot evaluate the flake identity (see error above)" >&2
    exit 1
  }
  got_home=$(nix eval --raw --impure --no-write-lock-file "$FLAKE#homeConfigurations.default.config.home.homeDirectory") || {
    echo "bootstrap: cannot evaluate the flake identity (see error above)" >&2
    exit 1
  }
  if [[ "$got_user" != "$want_user" || "${got_home%/}" != "$want_home" ]]; then
    echo "bootstrap: flake resolves to ($got_user, $got_home) but this account is ($want_user, $want_home)." >&2
    echo "bootstrap: run as the WSL login user; unset stale SUDO_USER or USER overrides." >&2
    exit 1
  fi
}

ensure_systemd() {
  grep -qE '^[[:space:]]*systemd[[:space:]]*=[[:space:]]*true' /etc/wsl.conf 2>/dev/null && return 0
  run sudo sh -c 'printf "[boot]\nsystemd=true\n" >> /etc/wsl.conf'
  action_needed "systemd enabled in /etc/wsl.conf. From Windows run: wsl.exe --shutdown, then re-run this script."
}

pkg_manager() {
  if command -v apt-get >/dev/null 2>&1; then echo apt
  elif command -v pacman >/dev/null 2>&1; then echo pacman
  elif command -v dnf >/dev/null 2>&1; then echo dnf
  elif command -v zypper >/dev/null 2>&1; then echo zypper
  else echo unknown
  fi
}

package_present() {
  case "$PKG_MANAGER" in
    apt) dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed' ;;
    pacman) pacman -Q "$1" >/dev/null 2>&1 ;;
    dnf|zypper) rpm -q "$1" >/dev/null 2>&1 ;;
    *) command -v "$1" >/dev/null 2>&1 ;;
  esac
}

install_packages() {
  case "$PKG_MANAGER" in
    apt) run sudo apt-get update; run sudo apt-get install -y "$@" ;;
    pacman)
      run sudo pacman -S --needed --noconfirm "$@" \
        || action_needed "pacman could not install $*. On a fresh Arch image run: sudo pacman -Syu, then re-run."
      ;;
    dnf) run sudo dnf install -y "$@" ;;
    zypper) run sudo zypper --non-interactive install "$@" ;;
    *) action_needed "no supported package manager found; install zsh git curl manually" ;;
  esac
}

locale_present() {
  locale -a 2>/dev/null | grep -qix 'en_US.utf8'
}

ensure_locale() {
  locale_present && return 0
  case "$PKG_MANAGER" in
    apt)
      run sudo locale-gen en_US.UTF-8
      ;;
    *)
      if [[ -f "$LOCALE_GEN" ]]; then
        if ! grep -qE '^[[:space:]]*en_US\.UTF-8[[:space:]]+UTF-8' "$LOCALE_GEN"; then
          if grep -qE '^[#[:space:]]*en_US\.UTF-8[[:space:]]+UTF-8' "$LOCALE_GEN"; then
            run sudo sed -i -E 's|^[#[:space:]]*(en_US\.UTF-8[[:space:]]+UTF-8)|\1|' "$LOCALE_GEN"
          else
            run sudo sh -c 'printf "en_US.UTF-8 UTF-8\n" >> "$1"' _ "$LOCALE_GEN"
          fi
        fi
        command -v locale-gen >/dev/null 2>&1 && run sudo locale-gen
      fi
      ;;
  esac
  if ! locale_present; then
    run sudo localedef -i en_US -f UTF-8 en_US.UTF-8
  fi
}

ensure_shell_and_locale() {
  local pkg shell zsh_path
  command -v getent >/dev/null 2>&1 || action_needed "getent is missing; install glibc/util-linux and re-run."
  PKG_MANAGER=$(pkg_manager)
  local -a missing=()
  for pkg in zsh git curl; do
    package_present "$pkg" || missing+=("$pkg")
  done
  if ((${#missing[@]})); then
    install_packages "${missing[@]}"
  fi
  zsh_path=/usr/bin/zsh
  [[ -x "$zsh_path" ]] || zsh_path=$(command -v zsh || echo /usr/bin/zsh)
  shell=$(getent passwd "$(id -un)" | cut -d: -f7)
  if [[ "$(readlink -f "$shell" 2>/dev/null)" != "$(readlink -f "$zsh_path" 2>/dev/null)" ]]; then
    run chsh -s "$zsh_path"
  fi
  ensure_locale
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

# Generate this instance's age key (never copied between instances).
ensure_age_key() {
  if [[ ! -f "$AGE_KEY_FILE" ]]; then
    run mkdir -p -m 700 "$(dirname "$AGE_KEY_FILE")"
    run nix shell "$FLAKE#age" -c age-keygen -o "$AGE_KEY_FILE"
    ((DRY_RUN)) || chmod 600 "$AGE_KEY_FILE"
  fi
  [[ -f "$AGE_KEY_FILE" ]] || return 0
  PUBKEY=$(public_key)
}

# Register this instance's key with the shared file only; a local-only
# instance must not modify wsl/.sops.yaml.
register_shared_recipient() {
  [[ -n "${PUBKEY:-}" ]] || return 0
  grep -qF -- "$PUBKEY" "$SOPS_CONFIG" || run register_recipient "$PUBKEY" "$SOPS_CONFIG"
}

check_secrets() {
  local status pub=${PUBKEY:-<this instance\'s age public key>}
  status=$(secrets_status "$SOPS_CONFIG" "$ACTIVE_SECRETS")
  case "$status" in
    ok) ;;
    missing)
      if [[ "$ACTIVE_SECRETS" == "$SECRETS_FILE" ]]; then
        action_needed "no secrets file yet. Create it (keys: ${SECRET_KEYS[*]}):
  cd $FLAKE && nix run .#sops -- --config $SOPS_CONFIG $SECRETS_FILE
then git add it and re-run. Or, to keep a local file for this instance only:
  bash ~/dotfiles/wsl/bootstrap.sh --new-secrets
(Otherwise, grant this instance access from one that can decrypt:
  bash ~/dotfiles/wsl/bootstrap.sh --add-recipient $pub)"
      else
        action_needed "no local secrets file at $ACTIVE_SECRETS. Remove it and re-run:
  bash ~/dotfiles/wsl/bootstrap.sh --new-secrets
or fill it with keys: ${SECRET_KEYS[*]}"
      fi
      ;;
    undecryptable)
      if [[ "$ACTIVE_SECRETS" == "$SECRETS_FILE" ]]; then
        action_needed "this instance's key cannot decrypt $SECRETS_FILE.
On an instance that can, run:
  bash ~/dotfiles/wsl/bootstrap.sh --add-recipient $pub
commit wsl/.sops.yaml and wsl/secrets/secrets.yaml there. Here, discard the local key
registration first so the pull can't conflict:
  cd $REPO && git checkout -- wsl/.sops.yaml
then pull that commit and re-run.
(Or re-create the file with this key only, which drops the other instances' access.)
Or run: bash ~/dotfiles/wsl/bootstrap.sh --new-secrets to create a local file."
      else
        action_needed "the local secrets file $ACTIVE_SECRETS cannot be decrypted by this instance.
Remove it and re-run:
  rm -f $ACTIVE_SECRETS
  bash ~/dotfiles/wsl/bootstrap.sh --new-secrets"
      fi
      ;;
    empty-keys:*)
      if [[ "$ACTIVE_SECRETS" == "$SECRETS_FILE" ]]; then
        action_needed "the shared secrets file has empty values: ${status#empty-keys:}. Fill them:
  nix run $FLAKE#sops -- --config \"$SOPS_CONFIG\" --filename-override secrets/secrets.yaml \"$ACTIVE_SECRETS\""
      fi
      echo "bootstrap: local secrets are empty (${status#empty-keys:}); continuing."
      echo "bootstrap: fill them later through sops:"
      echo "  EDITOR=vi SOPS_AGE_KEY_FILE=$AGE_KEY_FILE nix run $FLAKE#sops -- --config $SOPS_CONFIG --filename-override secrets/secrets.yaml $ACTIVE_SECRETS"
      ;;
    missing-keys:*)
      action_needed "$ACTIVE_SECRETS lacks: ${status#missing-keys:}. Add them:
  nix run $FLAKE#sops -- --config \"$SOPS_CONFIG\" --filename-override secrets/secrets.yaml \"$ACTIVE_SECRETS\""
      ;;
  esac
}

switch() {
  if [[ "$ACTIVE_SECRETS" != "$SECRETS_FILE" ]]; then
    export DOTFILES_WSL_SECRETS="$ACTIVE_SECRETS"
  fi
  # --impure lets home.nix read the account name and home directory from the
  # environment instead of a hardcoded user.
  local -a args=(switch --flake "$FLAKE#default" -b hm-backup --impure)
  args+=(--max-jobs 1 --cores 2)
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
  [[ -e "$HOME/.local/bin/claude" ]] && item "native claude (~/.local/bin/claude)" "rm -f $HOME/.local/bin/claude"
  [[ -e "$HOME/.opencode/bin/opencode" ]] && item "native opencode (~/.opencode/bin/opencode)" "rm -f $HOME/.opencode/bin/opencode"
  [[ -e "$HOME/.local/share/claude" ]] \
    && item "native claude payload (~/.local/share/claude)" "rm -rf $HOME/.local/share/claude"
  [[ -e "$HOME/.opencode" ]] \
    && item "native opencode install (~/.opencode)" "rm -rf $HOME/.opencode"
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
      --new-secrets) DO_NEW_SECRETS=1 ;;
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

  check_not_root
  check_location
  if [[ -n "$recipient" ]]; then
    add_recipient "$recipient"
    return 0
  fi

  ensure_systemd
  ensure_shell_and_locale
  ensure_nix
  check_identity
  ensure_submodules
  ensure_age_key
  resolve_secrets
  if [[ "$ACTIVE_SECRETS" == "$SECRETS_FILE" ]] && ((!DO_NEW_SECRETS)); then
    register_shared_recipient
  fi
  if ((DO_NEW_SECRETS)); then
    new_secrets
  fi
  check_secrets
  switch
  ((do_cleanup)) && cleanup
  return 0
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -euo pipefail
  main "$@"
fi
